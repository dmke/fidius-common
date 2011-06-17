require 'yaml'
require 'pp'
require 'rbconfig'
require 'highline/import'

# virtual boolean class. may create unforseen side effects (think of marshalling)
class Boolean
  self.private_class_method :new, :allocate
  def self.inherited(subclass)
    raise TypeError, "you cannot inherit #{subclass} from #{self}"
  end

  [::TrueClass, ::FalseClass].each{|bool_class|
    bool_class.class_eval %{
      def kind_of?(other)
        other == Boolean || super
      end
    }
  }
end

module FIDIUS
  module Configurator

    class << self
      def included(mod)
        mod.extend ConfigMethods
        mod.config.baseclass = mod
        mod.class_eval %{
          def config
            #{mod}.config
          end
        }
      end

      def config_file_name basename
        postfix = 'config', "#{basename}.yml"
        if RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
          File.join(ENV['APPDATA'], 'FIDIUS', *postfix)
        else
          File.join(ENV['HOME'], '.fidius', *postfix)
        end
      end
      
      def new(*args)
        return FIDIUS::Configurator::Configuration.new(*args)
      end
    end
    
    class ConfigItem < Struct.new(:type, :default, :question, :choices, :proc)
      def inspect
        "<##{self.class}: `#{question}` (#{type}) #{default}:#{choices}>"
      end
      
      def pretty_print(pp)
        pp.text inspect
      end
    end

    class Configuration
      include Enumerable

      attr_accessor :baseclass, :write_immediately
      attr_reader   :to_hash, :options

      def initialize
        @options = {}
        @to_hash = {}
        @read = false
        write_immediately = true
      end

      def add(hash)
        @options = items_from_hash(hash)
      end

      def [](key)
        read_config_file unless @read
        to_hash[key.to_s]
      end

      def []=(key, value)
        @to_hash[key.to_s] = value
        save if write_immediately
        value
      end

      def load
        @to_hash = YAML.load_file FIDIUS::Configurator.config_file_name(file_basename)
        @read = true
      rescue Errno::ENOENT
        generate_config_file
      end

      def save
        File.open(FIDIUS::Configurator.config_file_name(file_basename), 'w') {|f|
          f.write to_hash.to_yaml
        }
      end
      
      def inspect
        "<##{self.class} for #{baseclass}: #{to_hash.inspect}>"
      end

    private

      def items_from_array(args)
        p args
        default, proc, choices = nil, nil, nil
        type, question, *default_or_choices_or_proc = *args

        case type
        when Array
          choices = type
          type = type[0].class
        when Range
          choices = type
          type = type.first.class
        when TrueClass, FalseClass
          default = type
          type = Boolean
        when Class
          # everything's fine
        else
          default = type
          type = type.class
        end
        question = "#{baseclass} requests a #{type}" unless question
        question = "#{question}  "
        
        default_or_choices_or_proc.each {|dcp|
          if dcp.kind_of?(Proc)
            proc ||= dcp
          elsif dcp.kind_of?(Array) || dcp.kind_of?(Range)
            choices ||= dcp
          else
            default ||= dcp
          end
        }
#        case default_or_choices_or_proc.size
#        when 0
#          default ||= nil
#          choices ||= nil
#          proc ||= nil
#        when 1
#          dcp = default_or_choices_or_proc
#          if dcp[0].kind_of?(Proc)
#            proc = dcp[0]
#          elsif dcp[0].kind_of?(Array) || dcp[0].kind_of?(Range)
#            choices = dcp[0]
#          else
#            default = dcp[0]
#          end          
#        when 2
#          default = dcp[0]
#          proc = dcp[1]
#        when 3
#        end
        ConfigItem.new(type, default, question, choices, proc)
      end

      def items_from_hash(hash)
        options = {}
        hash.each_pair {|key,args|
          key = key.to_s
          if args.kind_of?(Array)
            options[key] = items_from_array(args)
          elsif args.kind_of?(Hash)
            options[key] = items_from_hash(args)
          else
            options[key] = items_from_array([args])
          end
        }
        options
      end

      def file_basename
        @file_basename ||= baseclass.to_s.gsub(/^FIDIUS::/, '').split('::').map(&:downcase).join('_')
      end

      def generate_config_file
        puts "Configuration missing for #{baseclass}. Creating new one..."
        @options.each_pair {|key,config_item|
          #  ask(question, answer_type = String, &details)
          if config_item.choices
            choose() {|q|
              q.prompt config_item.question
              q.choices config_item.choices, &nil
              q.validate = config_item.proc if config_item.proc
            }
          else
            ask(config_item.question, config_item.type) {|q|
              q.default  = config_item.default if config_item.default
              q.validate = config_item.proc if config_item.proc
            }
          end
        }
        puts "...done."
      end

    end # class Config

    module ConfigMethods
      def config
        @config ||= FIDIUS::Configurator::Configuration.new
      end
      def configure(config_hash)
        config.add(config_hash)
        config.load
      end
    end #module ConfigMethods

  end # module Config
end # module FIDIUS



##  Concept below. Features:
##    - few mandatory options, many optional
##    - simple or complex validation through customizable Proc objects
##    - arbritary nesting of options
##    - support for ranges and choices

if $0 == __FILE__
  module FIDIUS::Foo
    class Bar
      include FIDIUS::Configurator
      configure(
        # the key will be converted to string.
        # types of values:
#        :aval => [Integer],
#        :bval => [Integer, "a number"],
        :cval => [Integer, "a number with default", 42],
        :dval => [Integer, "a number with choices", [21,23,42]],
        :eval => [Integer, "a number with range", (1...100)],
        :xval => [Integer, "a number with range", 23, [21,23,42]],
        :yval => [Integer, "a number with range", 2, (1...100)]
#        :fval => [Integer, "a number with validation but w/o default", Proc.new{|val| val.to_i.even? }],
#        :gval => [Integer, "a number with validation and default", 0, Proc.new{|val| val.to_i.zero? }]#,
        # value nesting
#        :hval => {
#          :hvala => [String, "name a file", "~/.bashrc"],
#          :hvalb => [Boolean, "delete it?", true],
#          :hvalc => {
#            :hvalc1 => [Time, "using implicit conversation"]
#          }
#        },
#        # some useful shortcuts
#        :Cval  => [42,          "a number with default"], # identical to :cval
#        :Dval  => [[21,23,42],  "a number with choices"], # identical to :dval
#        :Eval  => [(1...100),   "a number with range"],   # do you see a pattern?
#        :Hvala => ["~/.bashrc", "name a file"],           # :
#        :Hvalb => [true,        "delete it?"]             # .
      )
    end
  end
end

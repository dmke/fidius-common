require 'yaml'
require 'fileutils'
require 'rbconfig'
require 'highline/import'

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
        target = FIDIUS::Configurator.config_file_name(file_basename)
        FileUtils.mkdir_p(File.dirname(target))
        File.open(target, 'w') {|f|
          f.write to_hash.to_yaml
        }
      end
      
      def inspect
        "<##{self.class} for #{baseclass}: #{to_hash.inspect}>"
      end

    private

      def items_from_array(args)
        default, range, choices, proc = nil, nil, nil, nil
        type, question, *default_or_choices_or_proc = *args

        case type
        when Array
          choices = type
          type = type[0].class
        when Range
          default = nil
          range = type
          type = type.first.class
          type = Integer if range.first.kind_of?(Integer)
        when TrueClass, FalseClass
          default = type
          type = type.class
        when Class
          # everything's fine
        when Integer
          default = type
          type = Integer
        else
          default = type
          type = type.class
        end
        
        default_or_choices_or_proc.each {|dcp|
          if dcp.kind_of?(Proc)
            proc ||= dcp
          elsif dcp.kind_of?(Array)
            choices ||= dcp
          elsif dcp.kind_of?(Range)
            range ||= dcp
          else
            default ||= dcp
          end
        }
        
        proc = Proc.new {|val| range.include?(val.to_i) } if range && !proc

        question = "#{baseclass} requests a #{type}" unless question
        question = "#{question} (#{range})" if range
        question = "#{question}  "

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
        @to_hash = generate_config_from_hash(@options)
        save
        puts "...done."
      end
      
      def generate_config_from_hash(hash)
        result = {}
        hash.each_pair {|key,config_item|
          result[key] = if config_item.kind_of?(Hash)
            generate_config_from_hash(config_item)
          elsif config_item.choices
            choose(*config_item.choices) {|q|
              q.prompt   = config_item.question
              q.validate = config_item.proc if config_item.proc
            }
          elsif config_item.type == TrueClass || config_item.type == FalseClass
            agree(config_item.question) {|q|
              q.default  = config_item.default ? 'yes' : 'no'
            }
          else
            ask(config_item.question, config_item.type) {|q|
              q.default  = config_item.default if config_item.default
              q.validate = config_item.proc if config_item.proc
            }
          end
        }
        result
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
        :aval => [Integer],
        :bval => [Integer, "a number"],
        :cval => [Integer, "a number with default", 42],
        :dval => [Integer, "a number with choices", [21,23,42]],
        :eval => [Integer, "a number with range", (1...100)],
        :xval => [Integer, "a number with range", 23, [21,23,42]],
        :yval => [Integer, "a number with range", 2, (1...100)],
        :fval => [Integer, "a number with validation but w/o default", Proc.new{|val| val.to_i.even? }],
        :gval => [Integer, "a number with validation and default", 0, Proc.new{|val| val.to_i.zero? }],
        # value nesting
        :hval => {
          :hvala => [String, "name a file", "~/.bashrc"],
          :hvalb => [TrueClass, "delete it?", true]
        },
        # some useful shortcuts
        :Cval  => [42,          "a number with default"], # identical to :cval
        :Dval  => [[21,23,42],  "a number with choices"], # identical to :dval
        :Eval  => [(1...100),   "a number with range"],   # do you see a pattern?
        :Hvala => ["~/.bashrc", "name a file"],           # :
        :Hvalb => [true,        "delete it?"],             # .
        :xxx => [true, "bla"]
      )
      
      p config
    end
  end
end

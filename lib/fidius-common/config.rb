require 'yaml'
require 'rbconfig'
require 'highline'

# virtual boolean class. may create unforseen side effects (think of marshalling)
# XXX: request feedback
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
  module Config

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
        if RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
          File.join(ENV['APPDATA'], 'FIDIUS', "#{basename}.yml")
        else
          File.join(ENV['HOME'], '.fidius', "#{basename}.yml")
        end
      end
    end

    class ConfigItem < Struct.new(:type, :question, :default, :validation)
      def get_from_user
        # highline
      end
    end

    class Config
      include Enumerable

      attr_accessor :baseclass, :write_immediately

      def initialize
        @options = {}
        @hsh = {}
        @read = false
        @write_immediately = true
      end

      def new(key, args)
        p args
        if args.kind_of? Hash
          options = new_from_hash(args)
        elsif args.kind_of? Array
          @options[key.to_s] = new_from_array(args)
        else
          new(key, [args])
        end

        if choices && default && !default.kind_of?(type)
          raise TypeError, "guess what? `#{default.inspect}' is not a #{type}"
        elsif default && !default.kind_of?(type)
          raise TypeError, "guess what? `#{default.inspect}' is not a #{type}"
        end
        @options[key] = ConfigItem.new(type, question, default)
      end

      def [](key)
        read_config_file unless @read
        @hsh[key.to_s]
      end

      def []=(key, value)
        @hsh[key.to_s] = value
        save if write_immediately
      end

      def load
        @hsh = YAML.load_file FIDIUS::Config.config_file_name(file_basename)
        @read = true
      rescue Errno::ENOENT
        generate_config_file
      end

      def save
        File.open(FIDIUS::Config.config_file_name(file_basename), 'w') {|f|
          f.write @hsh.to_yaml
        }
      end

      def to_hash
        @hsh
      end

      def inspect
        "<##{self.class} for #{baseclass}: #{@hsh.inspect}>"
      end

    private

      def new_from_array(args)
        default, proc = nil, nil
        type, question, *default_or_proc = *args

        case type
        when Array
          choices = type
          type = type[0].class
        when Range
          choices = type
          type = type.first.class
        when Class
          # everything's fine
        else
          default = type
          type = type.class
        end

        unless question
          question = "#{baseclass} requests a #{type}"
        end

        case default_or_proc.size
        when 0
          default ||= nil
        when 1
          if default_or_proc.kind_of?(Proc)
            proc = default_or_proc[0]
          else
            default = default_or_proc[0]
          end
        when 2
          default = default_or_proc[0]
          proc = default_or_proc[1]
        end
      end

      def new_from_hash(args)

      end

      def file_basename
        @file_basename ||= baseclass.to_s.gsub(/^FIDIUS::/, '').split('::').map(&:downcase).join('_')
      end

      def generate_config_file
        puts "FIDIUS::Config missing for #{baseclass}. Creating new one..."
        @options.each_pair {|key,config_item|
          # highline
        }
        puts "...done."
      end

    end # class Config

    module ConfigMethods
      def config
        @config ||= FIDIUS::Config::Config.new
      end
      def build_config(hsh)
        hsh.each_pair {|key,args| # FIXME: do it recursive
          config.new(key, args)
        }
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
      include FIDIUS::Config
      build_config(
        # the key will be converted to string.
        # types of values:
        :aval => [Integer],
        :bval => [Integer, "a number"],
        :cval => [Integer, "a number with default", 42],
        :dval => [Integer, "a number with choices", [21,23,42]],
        :eval => [Integer, "a number with range", (1...100)],
        :fval => [Integer, "a number with validation but w/o default", Proc.new{|val| val.even? }],
        :gval => [Integer, "a number with validation and default", 0, Proc.new{|val| val.zero? }],
        # value nesting
        :hval => {
          :hvala => [String, "name a file", "~/.bashrc"],
          :hvalb => [Boolean, "delete it?", true],
          :hvalc => {
            :hvalc1 => [Time, "using implicit conversation"]
          }
        },
        # some useful shortcuts
        :Cval  => [42,          "a number with default"], # identical to :cval
        :Dval  => [[21,23,42],  "a number with choices"], # identical to :dval
        :Eval  => [(1...100),   "a number with range"],   # do you see a pattern?
        :Hvala => ["~/.bashrc", "name a file"],           # :
        :Hvalb => [true,        "delete it?"]             # .
      )
    end
  end
end

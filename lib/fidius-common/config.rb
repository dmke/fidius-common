require 'yaml'
require 'pathname'
require 'fileutils'
require 'rbconfig'
require 'highline/import'

module FIDIUS
  module Configurator

    class << self
      # When +include+'ing the {Configurator} into another class or module,
      # that class or module will be extended with {ConfigMethods}.
      #
      # @param [Class|Module] mod  The class or module to be extended by {ConfigMethods}.
      # @param [void]
      def included(mod)
        mod.extend ConfigMethods
        mod.config.baseclass = mod
      end

      # Returns the +%APPDATA%+ or the +$HOME+ directory, based on the operation
      # system. Here, the configuration files are placed usually.
      #
      # @return [Pathname]  Returns either +%APPDATA%+ or +$HOME+, depending on
      #                     the operation system.
      def user_home
        @@user_home ||= if RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
          Pathname.new ENV['APPDATA']
        else
          Pathname.new ENV['HOME']
        end
      end
    end
    
    # This is a pure data container with comfortable accessors. Nothing special.
    class ConfigItem < Struct.new(:type, :default, :question, :choices, :proc)
      # Returns a human-readable representation.
      #
      # @return [String] A human-readable representation.
      def inspect
        "<##{self.class}: `#{question}` (#{type}) #{default}:#{choices}>"
      end

      # Generates output for the PrettyPrint library.
      #
      # @param [PP] pp  A pretty printer instance.
      # @return Output for PrettyPrint. See {#inspect}.
      def pretty_print(pp)
        pp.text inspect
      end
    end

    # A Hash-like config class. Each class or module including the {Configurator}
    # module is capable to use the {ConfigMethods#config} method to receive an
    # instance of this class.
    class Configuration
      include Enumerable

      attr_accessor :baseclass
      
      # Returns the configuration items as read from config file or as got from user input.
      # @return [Hash] The configuration items.
      attr_reader :to_hash
      alias :hash :to_hash

      def initialize
        @items   = {}
        @to_hash = {}
        @read    = false
        @options = {
          :read_immediately   => true,
          :write_immediately  => true,
          :configuration_root => 'FIDIUS',
          :assume_default     => false
        }
      end

      # Returns the component-specific configuration root directory. Unlike
      # {#config_file}, {#data_dir} and {#log_dir}, this directory won't immediately
      # be created.
      #
      # @return [Pathname]  The configuration root directory.
      def config_base_dir
        @config_base_dir ||= if RbConfig::CONFIG['host_os'] =~ /mswin|windows|cygwin/i
          Configurator.user_home + @options[:configuration_root]
        else
          Configurator.user_home + ".#{@options[:configuration_root]}"
        end
      end

      # Returns the path of the config file. The directory will be created, if
      # it does not exist yet.
      #
      # @return [Pathname] The config file name.
      def config_file
        @config_file_dir ||= begin
          path = config_base_dir + 'config'
          path.mkpath unless path.exist?
          path
        end
        @config_file ||= @config_file_dir + "#{file_basename}.yml"
      end

      # The directory returned could be used to store component-specific data.
      # This directory will be created if it does not exist and will not
      # automatically be flushed.
      #
      # @return [Pathname]  A data directory based on {#file_basename}.
      def data_dir
        @data_dir ||= begin
          path = config_base_dir + 'data' + file_basename
          path.mkpath unless path.exist?
          path
        end
      end

      # Creates and returns the log directory.
      #
      # @return [Pathname]  The log directory.
      def log_dir
        @log_dir ||= begin
          path = config_base_dir + 'log' + file_basename
          path.mkpath unless path.exist?
          path
        end
      end

      def add(hash)
        @items = @items.merge items_from_hash(hash)
      end

      # Accesses and return the value of an config option identified by +key+.
      # If the config file wasn't read yet (if you had have set the
      # +:read_immediately+ {#options= option} to +false+), it will be now.
      # This also implies the creation of that file if it does not exist.
      #
      # @param [#to_s] key  The option's identifier.
      # @return [Object]  The options's value identified by +key+.
      def [](key)
        read_config_file unless @read
        to_hash[key.to_s]
      end

      # Changes a specific option identified by +key+ and sets its value to +value+.
      #
      # @param [#to_s] key  The options' identifier.
      # @param [Object] value  An arbritary value to set.
      # @return [Object] The given +value+.
      def []=(key, value)
        @to_hash[key.to_s] = value
        save if options[:write_immediately]
        value
      end

      # This method tries to load a previously written config file. If this file does not exist, it will be created by
      # prompting the user for the configuration settings. You might also use the default options (and not prompting the
      # user) by setting the +:assume_default+ option to +true+ (see {#options=}).
      #
      # @return [void]
      def load
        @to_hash = YAML.load_file config_file
        @read = true
      rescue Errno::ENOENT
        generate_config_file
      end

      # Writes the configuration into a file, defined by the name of superclass et.al.
      #
      # @return [void]
      def save
        config_file.open('w') {|f|
          f.write to_hash.to_yaml
        }
      end
      
      # Modifies the configuration of the configurator. You may provide a Hash
      # with arbritary key/value pairs, but only the keys listed below will
      # have an effect on the behaviour.
      #
      # @note This method will only update those configuration options given
      #       by <tt>opts</tt>.
      #
      # @param [Hash] opts  A hash with various options.
      # @option opts [Boolean] :read_immediately (true)  When set to true, the
      #   config file will be read immediately after the {ConfigMethods#configure
      #   configure} method has captured the configuration options. Note, that
      #   this won't have any effect if not set directly as option for
      #   {ConfigMethods#configure configure}.
      # @option opts [Boolean] :write_immediately (true)  When set to true, the
      #   config file will be rewritten, whenever the configuration is updated.
      # @option opts [String] :configuration_root ('FIDIUS')  Names the root
      #   directory for the configuration files, log- and temporarily files
      #   within the users home or application directory. Depending on the
      #   operation system, this will be expanded to
      #   +$HOME/.:configuration_root/{config,log,tmp}/+ (unixoid) or
      #   +%APPDATA%\\:configuration_root\\{config,log,tmp}+ (MS Windows).
      # @option opts [Boolean] :assume_default (false)  In some situations,
      #   asking the end-user for configuration setting is not an option, e.g.
      #   when creating background daemons or when having a dumb terminal. In
      #   this case, you may set this option to +true+ and and the configuration
      #   wizard won't block any startup processes.
      #   
      #   *Beware:* Any given config item without default value will be ignored.
      #
      # @todo The :assume_default option is not implemented yet.
      #
      # @return [Hash]  The current configuration.
      def options= opts={}
        whitelist = [:read_immediately, :write_immediately, :configuration_root, :assume_default]
        opts.delete_if {|k,v| !whitelist.include?(k) }
        @options = @options.merge opts
      end
      
      # @return [String]  A human-readable representation.
      def inspect
        "<##{baseclass}::Configuration>"
      end

    private

      # @group Private Instance Method Summary

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
        @to_hash = generate_config_from_hash(@items)
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
      
      
      # @endgroup

    end # class Config

    # @todo Mention (define) "component" here.
    # @todo Inlude example code.
    module ConfigMethods
      # Returns the current {Configuration Configuration} instance for that
      # class or module, that has +include+d the {FIDIUS::Configurator
      # Configurator} module.
      def config
        @config ||= FIDIUS::Configurator::Configuration.new
      end
      
      # Genral discussion. 
      #
      # @overload configure(opts={}, config_items)
      #   Creates a configuration.
      #   @param [Hash] opts  The {Configuration Configuration}'s configuration.
      #     See {Configuration#options= #options=} there for details.
      #   @param [Hash] config_items  The component's configuration items.
      #
      # @overload configure(config_items)
      #   @param [Hash] config_items  The component's configuration items.
      def configure(*args)
        config_hash, options = args.pop, args.pop
        config.options = options if options
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
        :fval => [Integer, "a number with validation but w/o default", lambda {|val| val.to_i.even? }],
        :gval => [Integer, "a number with validation and default", 0, lambda {|val| val.to_i.zero? }],
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
        :Hvalb => [true,        "delete it?"],            # .
        :xxx => [true, "bla"]
      )
      
      p config.hash
    end
  end
  
  class Foo
    include FIDIUS::Configurator
    configure(
      :host => ["localhost", "A hostname"],
      :port => [(1..2**16),  "A port number"]
    )
  end
end

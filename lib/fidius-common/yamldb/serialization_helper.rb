# Copied and modified from yamldb gem (https://github.com/ludicast/yaml_db)
#
# Credits:
# Created by Orion Henry and Adam Wiggins.
# Major updates by Ricardo Chimal, Jr.
# Patches contributed by Michael Irwin, Tom Locke, and Tim Galeckas.
#
#This module deals with the serialization of the database schema and
#tables. It was extended by the establishment of the ActiveRecord
#connection to use the module without a Rails environment.
#
# dump_schema and load-schema are modified ActiveRecord rake-tasks.

module SerializationHelper

  class Base
    attr_reader :extension

    def initialize(helper, config_filename, db_entry)
      @dumper = helper.dumper
      @loader = helper.loader
      @extension = helper.extension

      establish_connection(config_filename, db_entry)
    end

    # Set configuration for the ActiveRecord connection.
    #
    # @param [String] path to yaml configuration file
    # @param [String] name of the db entry in the configuration file
    def establish_connection(yml_file, db_entry)
      if yml_file.class == String
        raise "#{yml_file} does not exist" unless File.exists? File.expand_path(yml_file)
        yml_config = YAML.load(File.read(yml_file))
        db_config = yml_config[db_entry]
      elsif yml_file.class == Hash
        # also react on connection settings given as hash
        db_config = yml_file
      else
        raise "please input string or hash"
      end
      unless db_config
        raise "No entry '#{db_entry}' found in #{yml_file}"
      else
        @db_entry = db_entry
        ActiveRecord::Base.establish_connection db_config
        ActiveRecord::Base.connection
      end
    end

    # copied and modified activerecord-3.0.6/lib/active_record/railties/database.rake
    def dump_schema
      require 'active_record/schema_dumper'
      File.open(File.join(@data_dir ,'schema.rb'), "w") do |file|
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
      end
    end

    def load_schema
      file = File.join(@data_dir ,'schema.rb')
      if File.exists?(file)
        ActiveSupport::Dependencies::Loadable.load(file)
      else
        puts "#{file} does not exist"
      end
    end

    # Added creation of directories with timestamps.
    # @param [String] path to target dir
    # @param [Boolean] true, if timestamp should be added
    def dump(target_dir, timestamp)
      unless target_dir.empty? and !Dir.exists?(target_dir)
        target_dir += '/'
      end
      dir = target_dir + @db_entry
      if timestamp
        timestamp = Time.now
        dir += "_#{timestamp.strftime("%Y-%m-%d_%H%M%S")}"
      end

      Dir.mkdir dir
      @data_dir = File.expand_path(dir)
      @data_filename = "#{@data_dir}/#{@db_entry}.#{@extension}"

      disable_logger
      dump_schema
      @dumper.dump(File.new(@data_filename, "w"))
      reenable_logger
      @data_dir
    end

    def load(import_dir ,truncate = true)
      if Dir.exists? import_dir
        @data_dir = import_dir
        disable_logger
        load_schema
        @loader.load(File.new("#{@data_dir}/#{@db_entry}.#{@extension}", "r"), truncate)
        reenable_logger
      else
        puts "#{import_dir} does not exist!"
      end
    end

    def disable_logger
      @@old_logger = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = nil
    end

    def reenable_logger
      ActiveRecord::Base.logger = @@old_logger
    end
  end

  class Load
    def self.load(io, truncate = true)
      ActiveRecord::Base.connection.transaction do
        load_documents(io, truncate)
      end
    end

    def self.truncate_table(table)
      begin
        ActiveRecord::Base.connection.execute("TRUNCATE #{SerializationHelper::Utils.quote_table(table)}")
      rescue Exception
        ActiveRecord::Base.connection.execute("DELETE FROM #{SerializationHelper::Utils.quote_table(table)}")
      end
    end

    def self.load_table(table, data, truncate = true)
      column_names = data['columns']
      if truncate
        truncate_table(table)
      end
      load_records(table, column_names, data['records'])
      reset_pk_sequence!(table)
    end

    def self.load_records(table, column_names, records)
      if column_names.nil?
        return
      end
      columns = column_names.map{|cn| ActiveRecord::Base.connection.columns(table).detect{|c| c.name == cn}}
      quoted_column_names = column_names.map { |column| ActiveRecord::Base.connection.quote_column_name(column) }.join(',')
      quoted_table_name = SerializationHelper::Utils.quote_table(table)
      records.each do |record|
        quoted_values = record.zip(columns).map{|c| ActiveRecord::Base.connection.quote(c.first, c.last)}.join(',')
        ActiveRecord::Base.connection.execute("INSERT INTO #{quoted_table_name} (#{quoted_column_names}) VALUES (#{quoted_values})")
      end
    end

    def self.reset_pk_sequence!(table_name)
      if ActiveRecord::Base.connection.respond_to?(:reset_pk_sequence!)
        ActiveRecord::Base.connection.reset_pk_sequence!(table_name)
      end
    end


  end

  module Utils

    def self.unhash(hash, keys)
      keys.map { |key| hash[key] }
    end

    def self.unhash_records(records, keys)
      records.each_with_index do |record, index|
        records[index] = unhash(record, keys)
      end

      records
    end

    def self.convert_booleans(records, columns)
      records.each do |record|
        columns.each do |column|
          next if is_boolean(record[column])
          record[column] = (record[column] == 't' or record[column] == '1')
        end
      end
      records
    end

    def self.boolean_columns(table)
      columns = ActiveRecord::Base.connection.columns(table).reject { |c| silence_warnings { c.type != :boolean } }
      columns.map { |c| c.name }
    end

    def self.is_boolean(value)
      value.kind_of?(TrueClass) or value.kind_of?(FalseClass)
    end

    def self.quote_table(table)
      ActiveRecord::Base.connection.quote_table_name(table)
    end

  end

  class Dump
    def self.before_table(io, table)

    end

    def self.dump(io)
      tables.each do |table|
        before_table(io, table)
        dump_table(io, table)
        after_table(io, table)
      end
    end

    def self.after_table(io, table)

    end

    def self.tables
      ActiveRecord::Base.connection.tables.reject { |table| ['schema_info', 'schema_migrations'].include?(table) }
    end

    def self.dump_table(io, table)
      return if table_record_count(table).zero?

      dump_table_columns(io, table)
      dump_table_records(io, table)
    end

    def self.table_column_names(table)
      ActiveRecord::Base.connection.columns(table).map { |c| c.name }
    end


    def self.each_table_page(table, records_per_page=1000)
      total_count = table_record_count(table)
      pages = (total_count.to_f / records_per_page).ceil - 1
      id = table_column_names(table).first
      boolean_columns = SerializationHelper::Utils.boolean_columns(table)
      quoted_table_name = SerializationHelper::Utils.quote_table(table)

      (0..pages).to_a.each do |page|
        sql = ActiveRecord::Base.connection.add_limit_offset!("SELECT * FROM #{quoted_table_name} ORDER BY #{id}",
                                                              :limit => records_per_page, :offset => records_per_page * page
                                                              )
        records = ActiveRecord::Base.connection.select_all(sql)
        records = SerializationHelper::Utils.convert_booleans(records, boolean_columns)
        yield records
      end
    end

    def self.table_record_count(table)
      ActiveRecord::Base.connection.select_one("SELECT COUNT(*) FROM #{SerializationHelper::Utils.quote_table(table)}").values.first.to_i
    end

  end

end

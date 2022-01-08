# frozen_string_literal: true

module OnlineMigrations
  # Class representing configuration options for the gem.
  class Config
    include ErrorMessages

    # The migration version starting from which checks are performed
    # @return [Integer]
    #
    attr_accessor :start_after

    # The database version against which the checks will be performed
    #
    # If your development database version is different from production, you can specify
    # the production version so the right checks run in development.
    #
    # @example Set specific target version
    #   OnlineMigrations.config.target_version = 10
    #
    attr_accessor :target_version

    # Whether to perform checks when migrating down
    #
    # Disabled by default
    # @return [Boolean]
    #
    attr_accessor :check_down

    # Error messages
    #
    # @return [Hash] Keys are error names, values are error messages
    # @example To change a message
    #   OnlineMigrations.config.error_messages[:remove_column] = "Your custom instructions"
    #
    attr_accessor :error_messages

    # Maximum allowed lock timeout value (in seconds)
    #
    # If set lock timeout is greater than this value, the migration will fail.
    # The default value is 10 seconds.
    #
    # @return [Numeric]
    #
    attr_accessor :lock_timeout_limit

    # List of tables with permanently small number of records
    #
    # These are usually tables like "settings", "prices", "plans" etc.
    # It is considered safe to perform most of the dangerous operations on them,
    #   like adding indexes, columns etc.
    #
    # @return [Array<String, Symbol>]
    #
    attr_reader :small_tables

    # Tables that are in the process of being renamed
    #
    # @return [Hash] Keys are old table names, values - new table names
    # @example To add a table
    #   OnlineMigrations.config.table_renames["users"] = "clients"
    #
    attr_accessor :table_renames

    # Columns that are in the process of being renamed
    #
    # @return [Hash] Keys are table names, values - hashes with old column names as keys
    #   and new column names as values
    # @example To add a column
    #   OnlineMigrations.config.column_renames["users] = { "name" => "first_name" }
    #
    attr_accessor :column_renames

    # Returns a list of custom checks
    #
    # Use `add_check` to add custom checks
    #
    # @return [Array<Array<Hash>, Proc>]
    #
    attr_reader :checks

    def initialize
      @table_renames = {}
      @column_renames = {}
      @error_messages = ERROR_MESSAGES
      @lock_timeout_limit = 10.seconds
      @checks = []
      @start_after = 0
      @small_tables = []
      @check_down = false
    end

    def small_tables=(table_names)
      @small_tables = table_names.map(&:to_s)
    end

    # Adds custom check
    #
    # @param start_after [Integer] migration version from which this check will be performed
    #
    # @yield [method, args] a block to be called with custom check
    # @yieldparam method [Symbol] method name
    # @yieldparam args [Array] method arguments
    #
    # @return [void]
    #
    # Use `stop!` method to stop the migration
    #
    # @example
    #   OnlineMigrations.config.add_check do |method, args|
    #     if method == :add_column && args[0].to_s == "users"
    #       stop!("No more columns on the users table")
    #     end
    #   end
    #
    def add_check(start_after: nil, &block)
      @checks << [{ start_after: start_after }, block]
    end
  end
end

# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    module MigrationHelpers
      # Backfills column data using background migrations.
      #
      # @param table_name [String, Symbol]
      # @param column_name [String, Symbol]
      # @param value
      # @param model_name [String] If Active Record multiple databases feature is used,
      #     the class name of the model to get connection from.
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_migration`
      #
      # @return [MigrationHelpers::BackgroundMigrations::Migration]
      #
      # @example
      #   backfill_column_in_background(:users, :admin, false)
      #
      # @example Additional background migration options
      #   backfill_column_in_background(:users, :admin, false, batch_size: 10_000)
      #
      # @note This method is better suited for extra large tables (100s of millions of records).
      #     For smaller tables it is probably better and easier to use more flexible `update_column_in_batches`.
      #
      # @note Consider `backfill_columns_in_background` when backfilling multiple columns
      #   to avoid rewriting the table multiple times.
      #
      def backfill_column_in_background(table_name, column_name, value, model_name: nil, **options)
        backfill_columns_in_background(table_name, { column_name => value },
                                       model_name: model_name, **options)
      end

      # Same as `backfill_column_in_background` but for multiple columns.
      #
      # @param updates [Hash] keys - column names, values - corresponding values
      #
      # @example
      #   backfill_columns_in_background(:users, { admin: false, status: "active" })
      #
      # @see #backfill_column_in_background
      #
      def backfill_columns_in_background(table_name, updates, model_name: nil, **options)
        model_name = model_name.name if model_name.is_a?(Class)

        enqueue_background_migration(
          "BackfillColumn",
          table_name,
          updates,
          model_name,
          **options
        )
      end

      # Copies data from the old column to the new column using background migrations.
      #
      # @param table_name [String, Symbol]
      # @param copy_from [String, Symbol] source column name
      # @param copy_to [String, Symbol] destination column name
      # @param model_name [String] If Active Record multiple databases feature is used,
      #     the class name of the model to get connection from.
      # @param type_cast_function [String, Symbol] Some type changes require casting data to a new type.
      #     For example when changing from `text` to `jsonb`. In this case, use the `type_cast_function` option.
      #     You need to make sure there is no bad data and the cast will always succeed
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_migration`
      #
      # @return [MigrationHelpers::BackgroundMigrations::Migration]
      #
      # @example
      #   copy_column_in_background(:users, :id, :id_for_type_change)
      #
      # @note This method is better suited for extra large tables (100s of millions of records).
      #     For smaller tables it is probably better and easier to use more flexible `update_column_in_batches`.
      #
      def copy_column_in_background(table_name, copy_from, copy_to, model_name: nil, type_cast_function: nil, **options)
        copy_columns_in_background(
          table_name,
          [copy_from],
          [copy_to],
          model_name: model_name,
          type_cast_functions: { copy_from => type_cast_function },
          **options
        )
      end

      # Same as `copy_column_in_background` but for multiple columns.
      #
      # @param type_cast_functions [Hash] if not empty, keys - column names,
      #   values - corresponding type cast functions
      #
      # @see #copy_column_in_background
      #
      def copy_columns_in_background(table_name, copy_from, copy_to, model_name: nil, type_cast_functions: {}, **options)
        model_name = model_name.name if model_name.is_a?(Class)

        enqueue_background_migration(
          "CopyColumn",
          table_name,
          copy_from,
          copy_to,
          model_name,
          type_cast_functions,
          **options
        )
      end

      # Creates a background migration for the given job class name.
      #
      # A background migration runs one job at a time, computing the bounds of the next batch
      # based on the current migration settings and the previous batch bounds. Each job's execution status
      # is tracked in the database as the migration runs.
      #
      # @param migration_name [String, Class] Background migration job class name
      # @param arguments [Array] Extra arguments to pass to the job instance when the migration runs
      # @option options [Symbol, String] :batch_column_name (primary key) Column name the migration will batch over
      # @option options [Integer] :min_value Value in the column the batching will begin at,
      #     defaults to `SELECT MIN(batch_column_name)`
      # @option options [Integer] :max_value Value in the column the batching will end at,
      #     defaults to `SELECT MAX(batch_column_name)`
      # @option options [Integer] :batch_size (20_000) Number of rows to process in a single background migration run
      # @option options [Integer] :sub_batch_size (1000) Smaller batches size that the batches will be divided into
      # @option options [Integer] :batch_pause (0) Pause interval between each background migration job's execution (in seconds)
      # @option options [Integer] :sub_batch_pause_ms (100) Number of milliseconds to sleep between each sub_batch execution
      # @option options [Integer] :batch_max_attempts (5) Maximum number of batch run attempts
      #
      # @return [OnlineMigrations::BackgroundMigrations::Migration]
      #
      # @example
      #   enqueue_background_migration("BackfillProjectIssuesCount",
      #       batch_size: 10_000, batch_max_attempts: 10)
      #
      #   # Given the background migration exists:
      #
      #   class BackfillProjectIssuesCount < OnlineMigrations::BackgroundMigration
      #     def relation
      #       Project.all
      #     end
      #
      #     def process_batch(projects)
      #       projects.update_all(
      #         "issues_count = (SELECT COUNT(*) FROM issues WHERE issues.project_id = projects.id)"
      #       )
      #     end
      #
      #     # To be able to track progress, you need to define this method
      #     def count
      #       Project.maximum(:id)
      #     end
      #   end
      #
      # @note For convenience, the enqueued background migration is run inline
      #     in development and test environments
      #
      def enqueue_background_migration(migration_name, *arguments, **options)
        options.assert_valid_keys(:batch_column_name, :min_value, :max_value, :batch_size, :sub_batch_size,
            :batch_pause, :sub_batch_pause_ms, :batch_max_attempts)

        migration_name = migration_name.name if migration_name.is_a?(Class)

        migration = Migration.create!(
          migration_name: migration_name,
          arguments: arguments,
          **options
        )

        # For convenience in dev/test environments
        if Utils.developer_env?
          runner = MigrationRunner.new(migration)
          runner.run_all_migration_jobs
        end

        migration
      end
    end
  end
end

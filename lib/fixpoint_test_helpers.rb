# Helper methods to be included into RSpec
module FixpointTestHelpers
  def restore_fixpoint(fixname, base: ActiveRecord::Base)
    @last_restored = fixname
    IncrementalFixpoint.from_file(fixname).load_into_database(base.connection)
  end

  # Compares the fixpoint with the records in the database.
  # If there is no such fixpoint yet, it will write a new one to the file system.
  # The latter is useful if the fixpoint was deleted to accommodate changes to it (see example in class description).
  #
  # +tables_to_compare+ can either be +:all+ or a list of table names (e.g. ['users', 'posts'])
  # +ignored_columns+ see Fixnum#records_for_table
  # +store_fixpoint_and_fail+ when given and the fixpoint does not already exist, a new fixpoint is created an the test will be marked pending/failed
  # +parent_fixname+ when storing a new fixpoint, use this as parent fixpoint (you can specify `:last_restored` then the last given to restore_fixpoint is used; not thread safe)
  # ---
  # If we refactor this to a gem, we should rely on rspec (e.g. use minitest or move comparison logic to Fixpoint class).
  # Anyhow, we keep it like this for now, because the expectations give much nicer output than the minitest assertions.
  def compare_fixpoint(fixname, ignored_columns=[:updated_at, :created_at], tables_to_compare: :all, store_fixpoint_and_fail: false, parent_fixname: nil, base: ActiveRecord::Base)
    if !IncrementalFixpoint.exists?(fixname)
      if store_fixpoint_and_fail
        store_fixpoint(fixname, parent_fixname)
        pending("Fixpoint \"#{fixname}\" did not exist yet. Skipping comparison, but created fixpoint from database. Try re-running the test.")
        fail
      else
        raise Fixpoint::Error, "Fixpoint #{fixname} does not exist"
      end
    end

    database_fp = IncrementalFixpoint.from_database(nil, base.connection)
    fixpoint_fp = IncrementalFixpoint.from_file(fixname)

    tables_to_compare = (database_fp.table_names + fixpoint_fp.table_names).uniq if tables_to_compare == :all
    tables_to_compare.each do |table_name|
      db_records = database_fp.records_for_table(table_name, ignored_columns)
      fp_records = fixpoint_fp.records_for_table(table_name, ignored_columns)

      # if a table is present in a fixpoint, there must be records in it because empty tables are stripped from fixpoints
      expect(db_records).not_to be_empty, "#{table_name} not in database, but in fixpoint"
      expect(fp_records).not_to be_empty, "#{table_name} not in fixpoint, but in database"
      # we assume that the order of records returned by SELECT is stable (so we do not do any sorting)
      expect(db_records).to eq(fp_records), "Database records for table \"#{table_name}\" did not match fixpoint \"#{fixname}\". Consider removing the fixpoint and re-running the test if the change is intended."
    end
  end

  # it is not a good idea to overwrite the fixpoint each time because timestamps may change (which then shows up in version control).
  # Hence we only provide a method to write to it if it does not exist.
  def store_fixpoint_unless_present(fixname, parent_fixname = nil, base: ActiveRecord::Base)
    store_fixpoint(fixname, parent_fixname, base: base) unless IncrementalFixpoint.exists?(fixname)
  end

  # +parent_fixname+ when given, only the (incremental) changes to the parent are saved
  # please see store_fixpoint_unless_present for note on why not to use this method
  def store_fixpoint(fixname, parent_fixname = nil, base: ActiveRecord::Base)
    parent_fixname = @last_restored if parent_fixname == :last_restored
    IncrementalFixpoint.from_database(parent_fixname, base.connection).save_to_file(fixname)
  end
end

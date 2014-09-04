# -*- encoding: utf-8 -*-
require_relative './util'

# Sequel validation is done using the database, so the definitions for task name
# need to be updated. This change is needed on both the table itself and the
# constraint validations table.
Sequel.migration do
  # Same as NAME_RX
  hook_name_rx = %r'\A[^\u0000-\u0020/\u0085\u00a0\u1680\u180e\u2000-\u200a\u2028\u2029\u202f\u205f\u3000](?:[^\u0000-\u001f/]*[^\u0000-\u0020/\u0085\u00a0\u1680\u180e\u2000-\u200a\u2028\u2029\u202f\u205f\u3000])?\Z(?!\n)'i

  up do
    extension(:constraint_validations)

    run %q{CREATE TYPE hook_events AS ENUM ('node_registered', 'node_bound',
                                     'node_reinstall', 'node_deleted')}

    create_table :hooks do
      primary_key :id
      String      :name, :null => false
      index       Sequel.function(:lower, :name),
                  :unique => true, :name => 'hooks_name_index'

      String      :hook_type, :null => false

      # JSON hash for the hook's current state
      String      :state, :null => false, :default => '{}'

      # We need to make sure that scripts for the same hook are serialized;
      # we do that by locking the hook. Since scripts can take a very long
      # time, we cannot do that with a database-level lock.
      #
      # The script processor will lock the hook before calling out to a
      # user-supplied script and unlock it after the script is done; we
      # store NULL when the hook is not locked, and the timestamp when the
      # lock was taken.
      #
      # If a hook ever fails so badly that it doesn't unlock the hook,
      # we'll forcibly unlock it after some time (i.e. when now() >
      # lock_time + max_allowed_script_duration)
      column      :lock_time, 'timestamp with time zone'
      foreign_key :locking_node, :nodes
      column      :locking_event, 'hook_events', :null => true
    end
  end

  down do
    extension(:constraint_validations)

    drop_table :hooks
    run %q{DROP TYPE hook_events}
  end
end

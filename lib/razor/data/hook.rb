# -*- encoding: utf-8 -*-

# Lifecycle and Events (starred events will be implemented later)
#   * node-booted (*)
#      - every time a node requests /svc/boot
#   * node-registered
#      - first time we get facts for a node (i.e., node.facts were nil before)
#   * node-facts-changed (*)
#      - from /svc/checkin every time facts change
#   * node-bound (C)
#      - when a node gets bound to a policy
#   * node-install-started (*)
#      - when booting into the first step of a task/policy for the first time
#   * node-install-finished (*)
#      - when Node.stage_done is called with name == "finished"
#   * node-broker-finished (*)
#      - we do not know that currently
#   * node-reinstall (C)
#      - when 'reinstall-node' command is run
#   * node-deleted (C)
#      - when 'delete-node' command is run

# Things to worry about
# 1. Events aren't 'done' until all hook scripts for it have finished
#    - can not fire 'next' event until previous one is done
#      -> going from bound-node to install-node; if binding triggers
#         an IP address lookup, we need to wait with install-node until that
#         is done

class Razor::Data::Hook < Sequel::Model
  plugin :serialization, :json, :state

  def handle(event, args)
    if script = find_script(event)
      # FIXME: args may contain Data objects; they need to be serialized
      # special
      # FIXME^2: we do this for Node, but it should be more general
      args[:node] = args[:node].pk_hash if args[:node]
      publish('run', event, script, args)
    end
  end

  # Run all hooks that have a handler for event
  def self.run(event, args)
    self.all { |hook| hook.handle(event, args) }
  end

  private

  # Check if this hook defines a handler script for event and return its
  # absolute path. Return nil if there is no such script
  def find_script(event)
    Razor.config.hook_paths.collect do |path|
      Pathname.new(path) + "#{name}.hook" + event
    end.find do |script|
      script.file? and script.executable?
    end
  end

  def run(event, script, args)
    return :retry unless lock!
    args[:node] = Razor::Data::Node[args[:node]] if args[:node]
    # @todo lutter 2014-07-01: how to render node as JSON ?
    hook_args = {
      name: name,
      state: state
    }
    result, output = exec_script(script, { hook: hook_args }.update(args))
    if result == 0
      # Success
      modify_state(output['hook']['state'])
      node.modify_metadata(output['node']['metadata'])
      save
      node.save
    else
      if result != 1
        log("Warning: script #{script} produced exit code #{result} when it should have been 0 or 1")
      end
      node.log(output['error'])
    end
  ensure
    unlock!
  end
end

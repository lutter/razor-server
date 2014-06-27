# Hooks

Hooks provide a way to be notified of certain events during the operation
of the Razor server; the behavior of a hook is defined by a *hook
type*.

## File layout for a hook type

Similar to brokers and tasks, hook types are defined through a `.hook`
directory and files within that directory:

    hooks/
      some.hook/
        configuration.yaml
        node-bind-policy
        node-unbind-policy
        ...

The hook type specifies the configuration data that it accepts in
`configuration.yaml`; that file must define a hash:

    foo:
      description: "Explain what foo is for"
      default: 0
    bar:
      description "Explain what bar is for"
      default: "Barbara"
    ...

For each event that the hook type handles, it must contain a script with
the event's name; that script must be executable by the Razor server. All
hook scripts for a certain event are run (in an indeterminate order) when
that event occurs.

## Creating hooks

The `cretae-hook` command is used to create a hook from a hook type:

    > razor create-hook --name myhook --hook-type some_hook \
        --configuration foo=7 --configuration bar=rhubarb

Similarly, the `delete-hook` command is used to remove a hook

## Event scripts

The general protocol is that hook event scripts receive a JSON object on
their stdin, and may return a result by printing a JSON object to their
stdout. The properties of the input object vary by event, but they always
contain a 'hook' property:

    {
      "hook": {
        "name": hook name,
        "config": ... user-defined object ...
      }
    }

The `config` object is initialized from the Hash described in the hook's
`configuration.yaml` and the properties set by the `create-hook`
command. With the `create-hook` command above, this would result in

    {
      "hook": {
        "name": "myhook",
        "config": {
          "foo": 7,
          "bar": "rhubarb"
        }
      }
    }

The script may return data by producing a JSON object on its stdout to
indicate changes that should be made to the hook's `config`; the updated
`config` will be used on subsequent invocations of any event for that
hook. The output must indicate which properties to update, and which ones
to remove:

    {
      "hook": {
        "config": {
          "update": {
            "foo": 8
          },
          "remove": [ "frob" ]
        }
      }
    }


The Razor server makes sure that invocations of hook scripts are
serialized; for any hook, events are processed one-by-one to make it
possible to provide transactional safety around the changes any event
script might make.

### Node events

Most events are directly related to a node. The JSON input to the event
script will have a `node` property which contains the representation of the
node in the same format as the API produces for node details.

The JSON output of the event script can modify the node metadata:

    {
      "node": {
        "metadata": {
          "update": {
            "foo": 8
          },
          "remove": [ "frob" ]
        }
      }
    }

### Error handling

The hook script must exit with exit code 0 if it succeeds; any other exit
code is considered a failure of the script. Whether the failure of a script
has any other effects depends on the event.

To report error details, the script should produce a JSON object with an
`error` property on its stdout in addition to exiting with a non-zero exit
code --- if the script exits with exit code 0 the `error` property will be
ignored. The `error` property should itself contain an object whose
`message` property is a human-readable message; additional properties can
be set. Example:

    {
      "error": {
        "message": "connection refused by frobnicate.example.com",
        "port": 2345,
        ...
      }
    }


## Available events

* `register-node`: triggered after a node has been registered, i.e. after
  its facts have been set for the first time by the Microkernel.
* `bound-node`: triggered after a node has been bound to a policy. The
  script input contains a `policy` property with the details of the
  policy that has been bound to the node.
* `reinstall-node`: triggered after a node has been marked as uninstalled
  by the `reinstall-node` command and thus been returned to the set of
  nodes available for installation.
* `delete-node`: triggered after a node has been deleted

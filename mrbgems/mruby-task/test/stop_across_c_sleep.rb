# A task stopped from C stays stopped across a sleep in the same C frame.
#
# mrb_stop_task() only marks the context MRB_TASK_STOPPED; it raises no
# switch request. sleep_us_impl() called with a C frame on the stack falls
# back to a blocking sleep and clears task.switching on its way out. So when
# TaskTest.stop_then_sleep returns, the VM sees no pending switch at all:
# the only thing that says the task is gone is c->status. The dispatch check
# has to read the status itself rather than reach it through the flag,
# otherwise the code after the probe runs in a task that no longer exists.

assert("a task stopped from C stays stopped across a sleep in the same C frame") do
  order = []

  Task.new(name: "stopper") do
    order << :before
    TaskTest.stop_then_sleep(Task.current)
    order << :after   # must never run
  end

  Task.run

  assert_equal [:before], order
end

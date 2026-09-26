# A wake-up raises a switch request only while a task is running.
#
# mrb_tick wakes a sleeping task by moving it to the ready queue. The switch
# request it raises with that is for whichever task has the CPU; when none
# does (the root context is running, or the scheduler is between tasks) the
# woken task is picked up from the ready queue at the next scheduler entry,
# and a request raised anyway would sit on the root context, where nothing
# acts on it and every control transfer reads it.
#
# The flag is watched from inside a C frame (TaskTest.wait_switch_pending):
# a Ruby loop polling it is itself a sequence of control transfers, and on a
# task context the VM's check would honor the flag at the first of them.

assert("a wake-up while the root context runs raises no switch request") do
  slice = TaskTest.timeslice_ms

  # Park one task in the sleep queue, then return to the root context with
  # it still asleep. Each mrb_task_run_once runs whichever task heads the
  # ready queue, so run until this one has gone to sleep.
  sleeper = Task.new(name: "sleeper") { sleep_ms slice * 2 }
  100.times do
    break if sleeper.status == :WAITING
    TaskTest.run_once
  end
  assert_equal :WAITING, sleeper.status

  begin
    # The root context is busy inside this C frame while the sleeper wakes.
    assert_false TaskTest.wait_switch_pending(slice * 20)
    assert_equal :READY, sleeper.status
  ensure
    # Let the sleeper finish so it does not outlive this test.
    Task.run
  end
end

assert("a wake-up while a task runs raises a switch request for it") do
  slice = TaskTest.timeslice_ms
  seen = nil

  # The sleeper runs first (same priority, created first) and goes to sleep;
  # the watcher then holds the CPU inside a C frame while the sleeper wakes.
  Task.new(name: "sleeper") { sleep_ms slice * 2 }
  Task.new(name: "watcher") { seen = TaskTest.wait_switch_pending(slice * 20) }
  Task.run

  assert_true seen
end

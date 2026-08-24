# Regression: mrb_execute_proc_synchronously() holds the scheduler lock and
# drives mrb_vm_exec() in a bare loop, so an early return has nowhere to go.
# If the VM honors a pending switch there it comes back having executed
# nothing, ci->pc unchanged and the flag still raised, and the loop calls it
# again. The temporary context it runs on also starts empty, so a C boundary
# that deferred the switch for the caller does not defer it here.
#
# Without the fix this spins rather than failing: on a computed-goto build the
# VM makes no progress at all, and on a switch-dispatch build it advances one
# instruction per call. Neither returns in any useful time, and a watchdog task
# cannot help, because the scheduler never regains control. The body is
# therefore kept to a handful of instructions, so an unfixed build hangs
# immediately and visibly at this test rather than looking slow.
if Object.const_defined?(:TaskTest) && TaskTest.respond_to?(:run_sync)
  assert('mruby-task: synchronous execution completes across a task wakeup') do
    sleeper = Task.new(name: "sleeper") { 4.times { sleep_ms 2 } }
    result = nil
    main = Task.new(name: "main") { result = TaskTest.run_sync { 40 + 2 } }
    Task.new(name: "stop") { sleep_ms 200; sleeper.terminate; main.terminate }
    Task.run

    assert_equal 42, result
  end
end

# The same loop entered while a switch is already pending, from inside the C
# frame that deferred it. Needs the burn helpers, so it is guarded separately.
if Object.const_defined?(:TaskTest) && TaskTest.respond_to?(:run_sync) &&
   TaskTest.respond_to?(:block_ms) && TaskTest.respond_to?(:timeslice_ms) &&
   TaskTest.respond_to?(:switch_pending?)
  assert('mruby-task: synchronous execution completes with a switch pending') do
    result = nil
    pending = nil
    Task.new(name: "sync") do
      Array.new(1) do
        TaskTest.block_ms(TaskTest.timeslice_ms * 3)
        pending = TaskTest.switch_pending?
        result = TaskTest.run_sync { 40 + 2 }
      end
    end
    Task.run

    assert_true pending, "no switch was pending, so the driver loop was not exercised"
    assert_equal 42, result
  end
end

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

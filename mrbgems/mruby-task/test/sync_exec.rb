# Regression: a synchronous execution must finish even when a sleeping task
# wakes up while it runs. mrb_execute_proc_synchronously() holds the
# scheduler lock and drives mrb_vm_exec() in a bare loop, so a context switch
# requested mid-run has nowhere to go: the VM returns having executed nothing
# and the loop calls it again, forever.
if Object.const_defined?(:TaskTest) && TaskTest.respond_to?(:run_sync)
  assert('mruby-task: synchronous execution completes across a task wakeup') do
    sleeper = Task.new(name: "sleeper") { 30.times { sleep_ms 2 } }
    result = nil
    main = Task.new(name: "main") do
      result = TaskTest.run_sync { s = 0; 300_000.times { |i| s += i }; s }
    end
    Task.new(name: "stop") { sleep_ms 5000; sleeper.terminate; main.terminate }
    Task.run

    assert_equal 44999850000, result
  end
end

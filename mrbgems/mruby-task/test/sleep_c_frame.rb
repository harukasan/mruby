# Regression: a task that sleeps while a C frame is on its stack must still be
# preemptable afterwards. sleep_us_impl() cannot switch contexts there, so it
# falls back to a blocking sleep. A switch the tick already requested has to
# survive that fallback. Dropping it strands the task: the timeslice arm fires
# on the edge where the counter reaches 0, and the counter is only reset in
# execute_task(), which a task that keeps running never reaches. Nothing else
# raises the flag until some other task wakes, so with no sleeper around the
# task runs to completion and no peer gets the CPU.
if Object.const_defined?(:TaskTest) && TaskTest.respond_to?(:block_ms) &&
   TaskTest.respond_to?(:timeslice_ms) && TaskTest.respond_to?(:switch_pending?)
  assert('mruby-task: a task stays preemptable after sleeping inside a C frame') do
    # Outlast the timeslice by a clear margin, derived from the build's own
    # constants rather than a literal, so raising MRB_TICK_UNIT cannot make the
    # block return before the switch is armed and quietly pass the test.
    block_ms = TaskTest.timeslice_ms * 3
    spinner_done = false
    spun = 0
    peer_count = 0
    peer_before = 0
    peer_after = 0
    deferred = nil
    pending = nil

    Task.new(name: "spin") do
      # Both calls run inside Array.new's block, so ci->cci > 0 holds
      # throughout: the timeslice expires while the switch cannot be honored,
      # and the sleep then takes the C-boundary fallback with it still pending.
      Array.new(1) do
        TaskTest.block_ms(block_ms)
        deferred = TaskTest.switch_deferred?
        pending = TaskTest.switch_pending?
        sleep_ms 1
      end
      # Spin until the peer is seen to advance, so the cost is one timeslice on
      # a fast machine rather than a fixed count, with a cap that turns a
      # tickless HAL into a bounded failure instead of a hang.
      peer_before = peer_count
      while peer_count == peer_before && spun < 20_000_000
        spun += 1
      end
      peer_after = peer_count
      spinner_done = true
    end

    # Bounded too: if the spinner dies before clearing the flag, this ends
    # rather than hanging the suite.
    Task.new(name: "peer") do
      i = 0
      while !spinner_done && i < 20_000_000
        i += 1
        peer_count += 1
      end
    end

    Task.run

    # The precondition that makes this the C-boundary case. If Array.new stops
    # dispatching its block through a C frame, sleep_ms takes the cooperative
    # path and the assertion below would hold while testing nothing.
    assert_true deferred, "sleep did not run behind a C frame, so the fallback was not exercised"
    assert_true pending, "no switch was pending, so there was nothing for the fallback to drop"
    assert_true peer_after > peer_before,
                "peer made no progress (#{peer_before} -> #{peer_after}) while " \
                "the spinner ran on after its C-frame sleep"
  end
end

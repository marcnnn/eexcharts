defmodule EexCharts.TimelineTest do
  use ExUnit.Case, async: true

  alias EexCharts.TimeScale

  defp labels(from, to, width) do
    from
    |> TimeScale.to_ms()
    |> TimeScale.ticks(TimeScale.to_ms(to), width)
    |> Enum.map(& &1.label)
  end

  describe "month scale" do
    test "names the year at January, as v4.7.0 does" do
      assert labels(~D[2024-01-01], ~D[2027-08-01], 800) == ["2024", "2025", "2026", "2027"]
    end

    test "stepped ticks snap to the calendar, not to the first data month" do
      # 6-month steps from June land on Jul / Jan, never on Jun / Dec.
      assert labels(~D[2024-06-01], ~D[2026-03-01], 800) == ["Jul '24", "2025", "Jul '25", "2026"]
    end
  end
end

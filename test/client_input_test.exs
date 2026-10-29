defmodule EexCharts.ClientInputTest do
  # Input that can come from outside the server: the size the measure hook
  # reports, and marker shape names taken from user data.
  use ExUnit.Case, async: true

  alias EexCharts.{Live, Marker}

  defp socket do
    Phoenix.Component.assign(%Phoenix.LiveView.Socket{},
      measured_width: nil,
      measured_height: nil
    )
  end

  defp measured(payload) do
    {:noreply, s} = Live.handle_event("measured", payload, socket())
    {s.assigns.measured_width, s.assigns.measured_height}
  end

  describe "the measured event" do
    test "keeps an ordinary size, rounded" do
      assert measured(%{"width" => 812.4, "height" => 400}) == {812, 400}
    end

    test "clamps each side to 1..10_000 px" do
      assert measured(%{"width" => 1.0e308, "height" => 0.2}) == {10_000, 1}
    end

    test "drops non-positive and non-numeric sides" do
      assert measured(%{"width" => -5, "height" => "300"}) == {nil, nil}
    end

    test "ignores a payload without both sides instead of crashing" do
      for payload <- [%{}, %{"width" => 800}, %{"size" => [1, 2]}] do
        assert {:noreply, _} = Live.handle_event("measured", payload, socket())
      end
    end
  end

  describe "marker shape names" do
    test "known names draw their shape" do
      assert Marker.path("square", 0, 0, 4) == Marker.path(:square, 0, 0, 4)
      assert Marker.path("rect", 0, 0, 4) == Marker.path(:square, 0, 0, 4)
      assert Marker.path("star", 0, 0, 4) == Marker.path(:star, 0, 0, 4)
    end

    test "unknown names fall back to a circle without creating atoms" do
      names = for i <- 1..200, do: "shape-#{i}-#{System.unique_integer([:positive])}"

      for name <- names do
        assert Marker.path(name, 0, 0, 4) == Marker.path(:circle, 0, 0, 4)
      end

      # Checked by name rather than by the VM's atom count, which tests running
      # concurrently move as they load modules.
      for name <- names do
        assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
      end
    end
  end
end

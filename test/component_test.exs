defmodule EexCharts.ComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  test "chart/1 renders inside HEEx" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <EexCharts.chart
        id="component-chart"
        type={:area}
        series={[%{name: "Revenue", data: [31, 40, 28, 51]}]}
        categories={~w(Q1 Q2 Q3 Q4)}
      />
      """)

    assert html =~ ~s(id="component-chart")
    assert html =~ "<svg"
    assert html =~ "Q3"
    assert html =~ ~s(phx-hook="EexCharts")
  end

  test "render/4 returns safe iodata for non-LiveView use" do
    {:safe, io} = EexCharts.render("plain", :pie, [1, 2, 3], labels: ~w(a b c), hook: false)
    html = IO.iodata_to_binary(io)

    assert html =~ ~s(id="plain")
    refute html =~ "phx-hook"
  end
end

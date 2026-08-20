defmodule EexCharts.TimeScale do
  @moduledoc """
  Datetime x-axis tick generation, ported (in spirit) from ApexCharts.js
  v4.7.0 `src/modules/TimeScale.js` and `src/utils/DateTime.js`.

  ApexCharts walks year/month/day/hour/minute/second boundaries with an
  incremental positioning algorithm; here we pick the tick *unit* using the
  same `determineInterval` thresholds and then emit unit-aligned boundary
  ticks, formatting each with ApexCharts' default `datetimeFormatter` strings.

  All timestamps are unix **milliseconds** (matching ApexCharts). Values are
  interpreted as UTC.
  """

  @ms_per_day 86_400_000
  @epoch ~N[1970-01-01 00:00:00]

  @short_months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @full_months ~w(January February March April May June July August September October November December)

  # Default xaxis.labels.datetimeFormatter format strings (Options.js).
  @formats %{
    year: "yyyy",
    month: "MMM 'yy",
    day: "dd MMM",
    hour: "HH:mm",
    minute: "HH:mm:ss",
    second: "HH:mm:ss"
  }

  @doc """
  Converts a supported x value to unix milliseconds.

  Accepts `DateTime`, `NaiveDateTime`, `Date`, an ISO-8601 binary, or a number
  (already unix milliseconds).
  """
  def to_ms(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)
  def to_ms(%NaiveDateTime{} = ndt), do: NaiveDateTime.diff(ndt, @epoch, :millisecond)
  def to_ms(%Date{} = d), do: to_ms(NaiveDateTime.new!(d, ~T[00:00:00]))
  def to_ms(n) when is_integer(n), do: n
  def to_ms(n) when is_float(n), do: round(n)

  def to_ms(str) when is_binary(str) do
    cond do
      match?({:ok, _, _}, DateTime.from_iso8601(str)) ->
        {:ok, dt, _} = DateTime.from_iso8601(str)
        to_ms(dt)

      match?({:ok, _}, NaiveDateTime.from_iso8601(str)) ->
        {:ok, ndt} = NaiveDateTime.from_iso8601(str)
        to_ms(ndt)

      match?({:ok, _}, Date.from_iso8601(str)) ->
        {:ok, d} = Date.from_iso8601(str)
        to_ms(d)

      true ->
        0
    end
  end

  @doc """
  Returns a list of `%{value: ms, label: binary, unit: atom}` ticks spanning
  `[min_ms, max_ms]`. `grid_width` sizes the target tick count (~1 per 150px,
  as ApexCharts does via `svgWidth / 150`).
  """
  def ticks(min_ms, max_ms, grid_width) when max_ms > min_ms do
    # Bounds can arrive as floats (a user-supplied `xaxis.min`, a computed
    # range). Everything below indexes the calendar in whole milliseconds, so
    # normalize once here rather than guarding every generator.
    {min_ms, max_ms} = {round(min_ms), round(max_ms)}

    span_days = (max_ms - min_ms) / @ms_per_day
    unit = determine_unit(span_days)
    target = max(2, round(grid_width / 150))

    unit
    |> generate(min_ms, max_ms, target)
    |> label_ticks(unit)
  end

  def ticks(_min, _max, _w), do: []

  # Sub-day ticks are labelled HH:mm, which says nothing about *which* day a
  # point belongs to once the range crosses midnight. Promote the first tick
  # of a new day to a date label. The very first tick keeps its time - there
  # is no previous day for it to contrast with.
  defp label_ticks(values, unit) when unit in [:hour, :minute, :second] do
    values
    |> Enum.map_reduce(nil, fn ms, prev ->
      date = ms |> DateTime.from_unix!(:millisecond) |> DateTime.to_date()
      label = format_date(ms, sub_day_format(unit, prev, date))
      {%{value: ms, unit: unit, label: label}, date}
    end)
    |> elem(0)
  end

  defp label_ticks(values, unit) do
    Enum.map(values, &%{value: &1, unit: unit, label: format_date(&1, @formats[unit])})
  end

  defp sub_day_format(unit, nil, _date), do: @formats[unit]
  defp sub_day_format(unit, same, same), do: @formats[unit]
  defp sub_day_format(_unit, _prev, _date), do: @formats[:day]

  # ── Interval selection (TimeScale.determineInterval) ──────────────────────

  defp determine_unit(days_diff) do
    years = days_diff / 365
    hours = days_diff * 24
    minutes = hours * 60

    cond do
      years > 5 -> :year
      days_diff > 180 -> :month
      days_diff > 2 -> :day
      hours > 2.4 -> :hour
      minutes > 5 -> :minute
      true -> :second
    end
  end

  # ── Tick generation ───────────────────────────────────────────────────────

  defp generate(:second, min, max, target),
    do: fixed(1_000, [1, 2, 5, 10, 15, 30], min, max, target)

  defp generate(:minute, min, max, target),
    do: fixed(60_000, [1, 2, 5, 10, 15, 30], min, max, target)

  defp generate(:hour, min, max, target),
    do: fixed(3_600_000, [1, 2, 3, 4, 6, 12], min, max, target)

  defp generate(:day, min, max, target),
    do: fixed(@ms_per_day, [1, 2, 5, 7, 14], min, max, target)

  defp generate(:month, min, max, target) do
    span_months = (max - min) / @ms_per_day / 30.44
    step = pick_step([1, 2, 3, 6, 12], span_months / target)

    {y, m} = month_of(min)
    # First month boundary at or after min, then step months apart.
    {sy, sm} = if month_start_ms(y, m) >= min, do: {y, m}, else: add_months(y, m, 1)

    Stream.iterate({sy, sm}, fn {yy, mm} -> add_months(yy, mm, step) end)
    |> Stream.map(fn {yy, mm} -> month_start_ms(yy, mm) end)
    |> Enum.take_while(&(&1 <= max))
  end

  defp generate(:year, min, max, target) do
    span_years = (max - min) / @ms_per_day / 365
    step = nice_year_step(span_years / target)

    {y, _m} = month_of(min)
    start_year = if year_start_ms(y) < min, do: y + 1, else: y
    # snap to a multiple of step for tidy labels
    start_year = start_year + rem(step - rem(start_year, step), step)

    Stream.iterate(start_year, &(&1 + step))
    |> Stream.map(&year_start_ms/1)
    |> Enum.take_while(&(&1 <= max))
  end

  # Fixed-duration units: align to a multiple of the step from the epoch.
  defp fixed(unit_ms, candidates, min, max, target) do
    raw = (max - min) / unit_ms / target
    step_ms = unit_ms * pick_step(candidates, raw)
    start = ceil_div(min, step_ms) * step_ms

    Stream.iterate(start, &(&1 + step_ms))
    |> Enum.take_while(&(&1 <= max))
  end

  defp pick_step(candidates, raw) do
    Enum.find(candidates, List.last(candidates), &(&1 >= raw)) |> max(1)
  end

  defp nice_year_step(raw) when raw <= 1, do: 1

  defp nice_year_step(raw) do
    pow = :math.pow(10, :math.floor(:math.log10(raw)))
    msd = raw / pow

    nice =
      cond do
        msd <= 1 -> 1
        msd <= 2 -> 2
        msd <= 5 -> 5
        true -> 10
      end

    max(round(nice * pow), 1)
  end

  # Ceiling division for non-negative `a` (timestamps). Elixir's `div`
  # truncates toward zero, so `-div(-a, b)` would floor here.
  defp ceil_div(a, b), do: Kernel.div(a + b - 1, b)

  # ── Calendar helpers (UTC) ─────────────────────────────────────────────────

  defp month_of(ms) do
    d = DateTime.from_unix!(ms, :millisecond)
    {d.year, d.month}
  end

  defp month_start_ms(year, month) do
    to_ms(NaiveDateTime.new!(Date.new!(year, month, 1), ~T[00:00:00]))
  end

  defp year_start_ms(year), do: month_start_ms(year, 1)

  defp add_months(year, month, n) do
    idx = year * 12 + (month - 1) + n
    {Kernel.div(idx, 12), rem(idx, 12) + 1}
  end

  # ── Date formatting (DateTime.formatDate) ──────────────────────────────────

  @doc """
  Formats a unix-millisecond timestamp using an ApexCharts format string.
  Supports `yyyy`, `yy`, `MMMM`, `MMM`, `MM`, `dd`, `HH`, `mm`, `ss`.
  """
  def format_date(ms, format) do
    d = DateTime.from_unix!(ms, :millisecond)

    replacements = [
      {"yyyy", pad(d.year, 4)},
      {"MMMM", "\x00"},
      {"MMM", "\x01"},
      {"MM", pad(d.month, 2)},
      {"dd", pad(d.day, 2)},
      {"HH", pad(d.hour, 2)},
      {"mm", pad(d.minute, 2)},
      {"ss", pad(d.second, 2)},
      {"yy", pad(rem(d.year, 100), 2)}
    ]

    format
    |> replace_all(replacements)
    |> String.replace("\x00", Enum.at(@full_months, d.month - 1))
    |> String.replace("\x01", Enum.at(@short_months, d.month - 1))
  end

  defp replace_all(str, replacements) do
    Enum.reduce(replacements, str, fn {token, value}, acc ->
      String.replace(acc, token, value)
    end)
  end

  defp pad(n, width), do: n |> Integer.to_string() |> String.pad_leading(width, "0")
end

defmodule EexCharts.Scale do
  @moduledoc """
  Y-axis scale computation, ported from ApexCharts.js v4.7.0
  `src/modules/Scales.js` (`niceScale`).

  Produces "nice" tick values covering the data range: the step size is
  snapped to a 1/2/5/10 mantissa, free endpoints are expanded to multiples of
  the step, and endpoints within 15% of zero are snapped to zero.
  """

  @js_precision 1.0e-11

  # Hard ceiling on the intervals a forced step may produce. Far above any
  # axis anyone can read; it exists only so a pathological step cannot build
  # a tick list unboundedly.
  @max_intervals 500

  # niceScaleDefaultTicks from Scales.js — values with many divisors,
  # indexed by round(max_ticks / 2).
  @default_ticks [
    1,
    2,
    4,
    4,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    6,
    12,
    12,
    12,
    12,
    12,
    12,
    12,
    12,
    12,
    24
  ]

  # niceScaleAllowedMagMsd — snaps the most significant digit of the raw
  # step to 1, 2, 5 or 10.
  @allowed_mag_msd [1, 1, 2, 5, 5, 5, 10, 10, 10, 10, 10]

  defstruct ticks: [], nice_min: 0, nice_max: 0, step: 1, log: false, log_base: 10

  @type t :: %__MODULE__{
          ticks: [number],
          nice_min: number,
          nice_max: number,
          step: number,
          log: boolean,
          log_base: number
        }

  @doc """
  Computes a nice scale for the data range `[y_min, y_max]`.

  Options:

    * `:min` / `:max` — user-forced endpoints
    * `:tick_amount` — user-forced number of intervals
    * `:step_size` — user-forced step
    * `:svg_height` — chart height used to estimate how many ticks fit
      (defaults to 350, mirroring ApexCharts' `(svgHeight - 100) / 15`)
  """
  @spec nice_scale(number, number, keyword | map) :: t
  def nice_scale(y_min, y_max, opts \\ []) do
    opts = Map.new(opts)
    svg_height = opts[:svg_height] || 350

    max_ticks = max((svg_height - 100) / 15, 2)

    got_min = is_number(opts[:min])
    got_max = is_number(opts[:max])
    got_tick_amount = is_number(opts[:tick_amount])
    # A non-positive forced step cannot produce ticks: zero divides by zero,
    # and a negative one walks away from the range forever. Treat it as unset
    # and fall back to the computed nice step.
    got_step_size = is_number(opts[:step_size]) and opts[:step_size] > 0

    y_min = if got_min, do: opts[:min], else: y_min
    y_max = if got_max, do: opts[:max], else: y_max

    ticks =
      if got_tick_amount do
        abs(round(opts[:tick_amount]))
      else
        idx = min(round(max_ticks / 2), length(@default_ticks) - 1)
        Enum.at(@default_ticks, idx)
      end

    # All-collapsed / empty data: synthesize a range.
    {y_min, y_max} =
      if not is_number(y_min) or not is_number(y_max) or (y_min == 0 and y_max == 0) do
        min0 = if got_min, do: y_min, else: 0
        max0 = if got_max, do: y_max, else: min0 + ticks
        {min0, max0}
      else
        {y_min, y_max}
      end

    # Sanity: swap inverted, expand degenerate ranges.
    {y_min, y_max} =
      cond do
        y_min > y_max -> {y_max, y_min}
        y_min == y_max and y_min == 0 -> {0, 2}
        y_min == y_max -> {y_min - 1, y_max + 1}
        true -> {y_min, y_max}
      end

    ticks = max(ticks, 1)
    range = abs(y_max - y_min)

    # Snap endpoints within 15% of zero onto zero.
    {y_min, got_min} =
      if not got_min and y_min > 0 and y_min / range < 0.15, do: {0, true}, else: {y_min, got_min}

    {y_max, got_max} =
      if not got_max and y_max < 0 and -y_max / range < 0.15,
        do: {0, true},
        else: {y_max, got_max}

    range = abs(y_max - y_min)

    # Nice step: snap most significant digit to 1/2/5/10.
    raw_step = range / ticks
    mag = floor(:math.log10(raw_step))
    mag_pow = :math.pow(10, mag)
    mag_msd = ceil(raw_step / mag_pow)
    mag_msd = Enum.at(@allowed_mag_msd, min(mag_msd, length(@allowed_mag_msd) - 1))
    step = if got_step_size, do: opts[:step_size] * 1.0, else: mag_msd * mag_pow

    {y_min, y_max, step, tiks} =
      cond do
        got_min and got_max ->
          # Range is fixed; honor tick_amount by dividing the range evenly.
          step = if got_tick_amount or not got_step_size, do: range / ticks, else: step
          {y_min * 1.0, y_max * 1.0, step, round(range / step)}

        got_max ->
          min2 = if got_tick_amount, do: y_max - step * ticks, else: step * ffloor(y_min / step)
          {min2, y_max * 1.0, step, round(abs(y_max - min2) / step)}

        got_min ->
          max2 = if got_tick_amount, do: y_min + step * ticks, else: step * fceil(y_max / step)
          {y_min * 1.0, max2, step, round(abs(max2 - y_min) / step)}

        true ->
          # Both free: expand to step multiples.
          min2 = step * ffloor(y_min / step)
          max2 = step * fceil(y_max / step)
          range2 = abs(max2 - min2)
          tiks = ceil((range2 - @js_precision) / (step + @js_precision))
          tiks = if tiks > 16 and length(prime_factors(tiks)) < 2, do: tiks + 1, else: tiks
          {min2, max2, range2 / tiks, tiks}
      end

    # Too many ticks to fit: thin them out via prime factors.
    {step, _tiks} =
      if tiks > max_ticks and not (got_tick_amount or got_step_size) do
        reduce_ticks(tiks, max_ticks, abs(y_max - y_min), step)
      else
        {step, tiks}
      end

    step = clamp_step(step, abs(y_max - y_min))
    ticks_list = build_ticks(y_min, y_max, step)

    %__MODULE__{
      ticks: ticks_list,
      nice_min: List.first(ticks_list),
      nice_max: List.last(ticks_list),
      step: step
    }
  end

  @doc """
  Logarithmic y-axis scale, ported from `Scales.js` `logarithmicScale` /
  `logarithmicScaleNice`.

  When `force_nice` is true, ticks land on exact powers of `base` bracketing
  the range (`logarithmicScaleNice`); otherwise ticks are evenly spaced in log
  space between `y_min` and `y_max` (`logarithmicScale`).

  ApexCharts falls back to a linear `nice_scale/3` when the range is `<= 5`
  (`invalidLogScale`); this mirrors that.
  """
  @spec log_scale(number, number, number, boolean) :: t
  def log_scale(y_min, y_max, base \\ 10, force_nice \\ false) do
    range = abs((y_max || 0) - (y_min || 0))

    if not is_number(y_min) or not is_number(y_max) or range <= 5 do
      nice_scale(y_min, y_max, [])
    else
      {ticks, nmin, nmax} =
        if force_nice do
          log_scale_nice(y_min, y_max, base)
        else
          log_scale_plain(y_min, y_max, base)
        end

      %__MODULE__{
        ticks: Enum.map(ticks, &strip_number/1),
        nice_min: nmin,
        nice_max: nmax,
        step: 1,
        log: true,
        log_base: base
      }
    end
  end

  defp log_scale_plain(y_min, y_max, base) do
    y_max = if y_max <= 0, do: max(y_min, base), else: y_max
    y_min = if y_min <= 0, do: min(y_max, base), else: y_min

    lb = :math.log(base)
    log_max = :math.log(y_max) / lb
    log_min = :math.log(y_min) / lb
    log_range = log_max - log_min
    ticks = max(round(log_range), 1)
    spacing = log_range / ticks

    logs =
      Enum.map(0..(ticks - 1), fn i -> :math.pow(base, log_min + i * spacing) end) ++
        [:math.pow(base, log_max)]

    {logs, y_min, y_max}
  end

  defp log_scale_nice(y_min, y_max, base) do
    y_max = if y_max <= 0, do: max(y_min, base), else: y_max
    y_min = if y_min <= 0, do: min(y_max, base), else: y_min

    lb = :math.log(base)
    log_max = ceil(:math.log(y_max) / lb + 1)
    log_min = floor(:math.log(y_min) / lb)

    logs = Enum.map(log_min..(log_max - 1), fn i -> :math.pow(base, i) end)
    {logs, List.first(logs), List.last(logs)}
  end

  @doc """
  Evenly-spaced linear ticks for the x-axis, ported from `Scales.js`
  `linearScale`. Produces `ticks + 1` values from `x_min` in steps of
  `range / ticks` (or the forced `step`). Returns `{result, nice_min,
  nice_max}`.
  """
  @spec linear_scale(number, number, number, number | nil) :: {[number], number, number}
  def linear_scale(x_min, x_max, ticks, step \\ nil)

  def linear_scale(x, x, _ticks, _step), do: {[x], x, x}

  def linear_scale(x_min, x_max, ticks, step) do
    range = abs(x_max - x_min)

    # A forced step is authoritative: derive the tick count from it so the last
    # tick lands on (or just past) x_max rather than overshooting by ticks-worth.
    {ticks, step} =
      if is_number(step) and step > 0 do
        {max(round(range / step), 1), step}
      else
        t = max(round(ticks), 1)
        {t, range / t}
      end

    # Utils.preciseAddition, then 7 significant digits to clear float drift.
    # A fixed 2 decimals truncates any range under ~0.1 - the step collapses
    # and the axis stops short of x_max, drawing points outside the grid.
    step = strip_number(step + 2.2e-16)
    step = if step == 0, do: range / ticks, else: step

    result = Enum.map(0..ticks, fn i -> strip_number(x_min + i * step) end)

    {result, List.first(result), List.last(result)}
  end

  # A forced step far smaller than the range would iterate essentially
  # forever. Widen it to something the axis could actually draw instead of
  # handing back a list the caller cannot use.
  defp clamp_step(step, range) when step > 0 and range / step > @max_intervals,
    do: range / @max_intervals

  defp clamp_step(step, _range), do: step

  defp build_ticks(y_min, _y_max, step) when step <= 0, do: [strip_number(y_min)]

  defp build_ticks(y_min, y_max, step) do
    err = step * @js_precision

    Stream.iterate(y_min, &(&1 + step))
    |> Enum.take_while(fn v -> v - y_max <= err end)
    |> Enum.map(&strip_number/1)
    |> case do
      [] -> [strip_number(y_min)]
      list -> list
    end
  end

  defp reduce_ticks(tiks, max_ticks, range, _step) do
    factors = prime_factors(tiks)

    reduced =
      Enum.reduce_while(products(factors), nil, fn p, _acc ->
        if tiks / p < max_ticks, do: {:halt, tiks / p}, else: {:cont, nil}
      end)

    case reduced do
      nil -> {range, 1}
      tt -> {range / tt, round(tt)}
    end
  end

  # All products of subsets of the prime factors, ascending.
  defp products(factors) do
    factors
    |> Enum.reduce([1], fn f, acc -> acc ++ Enum.map(acc, &(&1 * f)) end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.drop(1)
  end

  @doc false
  def prime_factors(n) when n < 2, do: []

  def prime_factors(n), do: prime_factors(n, 2, [])

  defp prime_factors(1, _d, acc), do: Enum.reverse(acc)

  defp prime_factors(n, d, acc) when d * d > n, do: Enum.reverse([n | acc])

  defp prime_factors(n, d, acc) do
    if rem(n, d) == 0 do
      prime_factors(div(n, d), d, [d | acc])
    else
      prime_factors(n, d + 1, acc)
    end
  end

  @doc """
  Rounds to 7 significant digits, removing floating point drift
  (ApexCharts `Utils.stripNumber`).
  """
  def strip_number(v) when is_integer(v), do: v

  def strip_number(v) when is_float(v) do
    stripped =
      v
      |> :erlang.float_to_binary([{:scientific, 6}])
      |> String.to_float()

    if stripped == trunc(stripped) and abs(stripped) < 1.0e15, do: trunc(stripped), else: stripped
  end

  defp ffloor(v), do: :math.floor(v)
  defp fceil(v), do: :math.ceil(v)
end

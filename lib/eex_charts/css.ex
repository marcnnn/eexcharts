defmodule EexCharts.CSS do
  @moduledoc """
  The gate every CSS value passes on its way into the markup.

  Colors, font families and similar options are written into `style`
  attributes and SVG presentation attributes. HTML escaping keeps them from
  closing the attribute, but not from adding CSS of their own: a color of
  `red;background:url(https://example.com/x)` would add a declaration that
  makes the browser fetch that URL. Options and series often come from user
  data (a saved dashboard, a per-series color picker), so `EexCharts.SVG`
  checks each such value with `safe_value?/1` and leaves out any that fails.

  A safe value is one CSS value, never more than one declaration:

    * letters, digits, whitespace, quotes and `# % . , + - _ / * ( )`;
      no `;`, `:`, `{`, `}`, `\\`, `!`, `@` or comment opener;
    * only the color and math functions `rgb()`, `rgba()`, `hsl()`,
      `hsla()`, `hwb()`, `lab()`, `lch()`, `oklab()`, `oklch()`, `color()`,
      `color-mix()`, `var()`, `calc()`, `min()`, `max()` and `clamp()`;
    * `url()` only as a same-document reference such as `url(#grad-1)`,
      which is how gradients and clip paths are referenced;
    * balanced quotes.

  Everything a chart accepts as a color (hex, named colors, the CSS color
  functions, daisyUI's `var(--color-primary, …)`) and every ordinary font
  stack passes.
  """

  @functions ~w(rgb rgba hsl hsla hwb lab lch oklab oklch color color-mix var calc min max clamp)

  @same_document_url ~r/url\(\s*#[^()'"\\\s]*\s*\)/i
  @allowed_chars ~r/\A[\p{L}\p{N}\s#%.,()+\-_\/*'"]*\z/u
  @function_call ~r/([\p{L}\p{N}_-]*)\(/u

  @doc "Whether `value` can be written into CSS as a single value."
  def safe_value?(value) when is_number(value), do: true
  def safe_value?(value) when is_atom(value), do: value |> Atom.to_string() |> safe_value?()

  def safe_value?(value) when is_binary(value) do
    rest = Regex.replace(@same_document_url, value, "")

    Regex.match?(@allowed_chars, rest) and
      not String.contains?(rest, "/*") and
      known_functions?(rest) and
      balanced_quotes?(rest)
  end

  def safe_value?(_value), do: false

  defp known_functions?(value) do
    @function_call
    |> Regex.scan(value, capture: :all_but_first)
    |> Enum.all?(fn [name] -> String.downcase(name) in @functions end)
  end

  defp balanced_quotes?(value) do
    rem(count(value, "\""), 2) == 0 and rem(count(value, "'"), 2) == 0
  end

  defp count(value, char), do: length(:binary.split(value, char, [:global])) - 1
end

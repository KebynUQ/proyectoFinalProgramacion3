defmodule Trivia.BotTest do
  use ExUnit.Case

  test "bot siempre devuelve letra válida y retraso según dificultad" do
    Enum.each(["facil", "dificil"], fn dificultad ->
      Enum.each(["basico", "intermedio", "avanzado"], fn nivel ->
        Enum.each(1..30, fn _ ->
          {letra, retardo} = Trivia.Bot.decision(dificultad, nivel, "B", 10_000)
          assert letra in ["A", "B", "C", "D"]
          {minimo, maximo} = if dificultad == "facil", do: {4000, 9000}, else: {1000, 4000}
          assert retardo >= minimo and retardo <= maximo
        end)
      end)
    end)
  end
end

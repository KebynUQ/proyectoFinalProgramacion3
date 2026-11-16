defmodule Trivia.BancoPreguntasTest do
  use ExUnit.Case

  setup do
    start_supervised!(Trivia.BancoPreguntas)
    :ok
  end

  test "cuatro temas y selección sin preguntas repetidas" do
    assert length(Trivia.BancoPreguntas.temas()) >= 4
    assert :ok == Trivia.BancoPreguntas.disponibles?("ciencia", "basico", 5)
    assert {:error, _} = Trivia.BancoPreguntas.disponibles?("inexistente", "basico", 5)
    assert {:ok, elegidas} = Trivia.BancoPreguntas.seleccionar("ciencia", "basico", 5)
    assert length(elegidas) == 5
    assert Enum.all?(elegidas, fn p -> p["tema"] == "ciencia" end)
    assert length(Enum.uniq_by(elegidas, fn p -> p["id"] end)) == 5
    assert Enum.count(elegidas, fn p -> p["nivel"] == "basico" end) == 4
    assert Enum.count(elegidas, fn p -> p["nivel"] == "intermedio" end) == 1
    assert Enum.map(elegidas, fn p -> p["nivel"] end) == ["basico", "basico", "basico", "basico", "intermedio"]
  end
end

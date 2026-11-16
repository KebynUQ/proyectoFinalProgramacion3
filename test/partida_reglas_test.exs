defmodule Trivia.PartidaReglasTest do
  use ExUnit.Case

  test "valida capacidad y estado para incorporar bots" do
    assert Trivia.Partida.validar_agregar_bot(:esperando, 0) == :ok
    assert Trivia.Partida.validar_agregar_bot(:esperando, 3) == {:error, "La partida está llena"}
    assert match?({:error, _}, Trivia.Partida.validar_agregar_bot(:en_curso, 1))
  end

  test "exige al menos dos bots para comenzar" do
    assert match?({:error, _}, Trivia.Partida.validar_comienzo(:esperando, 1))
    assert Trivia.Partida.validar_comienzo(:esperando, 2) == :ok
    assert match?({:error, _}, Trivia.Partida.validar_comienzo(:en_curso, 2))
  end
end

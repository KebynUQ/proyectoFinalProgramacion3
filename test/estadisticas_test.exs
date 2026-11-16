defmodule Trivia.EstadisticasTest do
  use ExUnit.Case

  test "reconstruye puntos, temas y partidas desde el historial" do
    historial = [
      %{"tema" => "ciencia", "puntajes" => %{"ana" => 40, "bot_1" => 80}},
      %{"tema" => "ciencia", "puntajes" => %{"ana" => 25, "bot_1" => 30}},
      %{"tema" => "historia", "puntajes" => %{"ana" => -10, "bot_2" => 5}}
    ]

    datos = Trivia.Nivel.estadisticas(historial, "ana")
    assert datos.puntaje == 55
    assert datos.partidas == 3
    assert datos.temas == %{"ciencia" => 65, "historia" => -10}
    assert Trivia.Nivel.nivel_usuario(historial, "ana", "ciencia") == "intermedio"
    assert Trivia.Nivel.nivel_usuario(historial, "ana", "geografia") == "basico"
    assert Trivia.Nivel.ranking(historial) == [{"ana", %{puntaje: 55, partidas: 3}}]
    assert Trivia.Nivel.ranking(historial, "ciencia") == [{"ana", %{puntaje: 65, partidas: 2}}]
  end
end

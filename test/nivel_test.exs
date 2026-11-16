defmodule Trivia.NivelTest do
  use ExUnit.Case

  test "umbrales de nivel, incluyendo puntajes negativos" do
    assert Trivia.Nivel.desde_puntos(-5) == "basico"
    assert Trivia.Nivel.desde_puntos(59) == "basico"
    assert Trivia.Nivel.desde_puntos(60) == "intermedio"
    assert Trivia.Nivel.desde_puntos(179) == "intermedio"
    assert Trivia.Nivel.desde_puntos(180) == "avanzado"
  end

  test "reparto de preguntas según nivel con truncamiento" do
    assert Trivia.Nivel.reparto("basico", 5) == %{"basico" => 4, "intermedio" => 1, "avanzado" => 0}
    assert Trivia.Nivel.reparto("intermedio", 10) == %{"basico" => 2, "intermedio" => 6, "avanzado" => 2}
    assert Trivia.Nivel.reparto("avanzado", 10) == %{"basico" => 0, "intermedio" => 3, "avanzado" => 7}
  end
end

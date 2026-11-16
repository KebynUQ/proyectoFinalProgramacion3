defmodule Trivia.PuntajeTest do
  use ExUnit.Case

  test "puntajes correctos por dificultad, bonus proporcional y dos tiempos" do
    assert Trivia.Puntaje.calcular("basico", "A", "A", 14_000, 15_000) == 14
    assert Trivia.Puntaje.calcular("intermedio", "A", "A", 11_000, 15_000) == 18
    assert Trivia.Puntaje.calcular("avanzado", "A", "A", 6_000, 15_000) == 22
    assert Trivia.Puntaje.calcular("basico", "A", "A", 28_000, 30_000) == 14
    assert Trivia.Puntaje.calcular("avanzado", "A", "A", 0, 30_000) == 20
  end

  test "respuesta incorrecta o ausente" do
    assert Trivia.Puntaje.calcular("basico", "B", "A", 14_000, 15_000) == -5
    assert Trivia.Puntaje.calcular("intermedio", "B", "A", 14_000, 15_000) == -8
    assert Trivia.Puntaje.calcular("avanzado", "B", "A", 14_000, 15_000) == -10
    assert Trivia.Puntaje.calcular("avanzado", nil, "A", 14_000, 15_000) == 0
  end
end

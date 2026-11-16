defmodule Trivia.RespuestasTest do
  use ExUnit.Case

  test "rechaza letras inválidas sin ocupar la respuesta y bloquea segundas respuestas" do
    abierta = %{estado: :en_curso, ronda_abierta: true, respuestas: %{}}
    assert Trivia.Partida.validar_respuesta(abierta, "pedro", "E") ==
      {:error, "Solo puedes responder A, B, C o D"}

    # El intento inválido no queda registrado: se puede contestar A.
    assert Trivia.Partida.validar_respuesta(abierta, "pedro", "A") == :ok

    respondida = %{abierta | respuestas: %{"pedro" => %{letra: "A", restantes_ms: 1000}}}
    assert Trivia.Partida.validar_respuesta(respondida, "pedro", "B") ==
      {:error, "Ya respondiste esta ronda"}
  end

  test "rechaza respuestas cuando la ronda no está abierta" do
    pausa = %{estado: :en_curso, ronda_abierta: false, respuestas: %{}}
    assert Trivia.Partida.validar_respuesta(pausa, "pedro", "A") ==
      {:error, "No hay ninguna ronda abierta"}
  end
end

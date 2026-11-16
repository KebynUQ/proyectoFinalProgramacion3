defmodule Trivia.Application do
  @moduledoc "Inicia los procesos del servidor solamente en su nodo."
  use Application

  def start(_tipo, _argumentos) do
    nombre = Atom.to_string(node())

    hijos =
      if String.starts_with?(nombre, "servidor@") do
        [
          Trivia.Persistencia,
          Trivia.BancoPreguntas,
          Trivia.GestorJugadores,
          {DynamicSupervisor, strategy: :one_for_one, name: Trivia.SupervisorPartidas},
          Trivia.GestorPartidas,
          Trivia.Servidor
        ]
      else
        []
      end

    resultado = Supervisor.start_link(hijos, strategy: :one_for_one, name: Trivia.Supervisor)
    if hijos != [] and match?({:ok, _}, resultado) do
      IO.puts("Servidor central de Trivia iniciado. Esperando clientes...")
    end
    resultado
  end
end

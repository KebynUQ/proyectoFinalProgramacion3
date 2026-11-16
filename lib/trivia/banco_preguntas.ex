defmodule Trivia.BancoPreguntas do
  @moduledoc "Carga y selecciona preguntas por tema y dificultad desde el servidor."
  use GenServer

  def start_link(_argumentos \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def disponibles?(tema, nivel, total),
    do: GenServer.call(__MODULE__, {:disponibles, tema, nivel, total})

  def seleccionar(tema, nivel, total),
    do: GenServer.call(__MODULE__, {:seleccionar, tema, nivel, total})

  def temas, do: GenServer.call(__MODULE__, :temas)

  def init(:ok) do
    ruta = Path.join([File.cwd!(), "data", "questions.json"])

    with {:ok, contenido} <- File.read(ruta),
         {:ok, preguntas} <- Jason.decode(contenido),
         :ok <- validar_banco(preguntas) do
      {:ok, preguntas}
    else
      error -> {:stop, {:banco_preguntas_invalido, error}}
    end
  end
end

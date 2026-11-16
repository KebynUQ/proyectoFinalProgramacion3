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
    defp validar_banco(preguntas) when not is_list(preguntas),
    do: {:error, "questions.json debe contener una lista"}

  defp validar_banco(preguntas) do
    revision =
      preguntas
      |> Enum.with_index(1)
      |> Enum.reduce(:ok, fn {pregunta, numero}, resultado ->
        case resultado do
          :ok ->
            case validar_pregunta(pregunta) do
              :ok -> :ok
              {:error, detalle} -> {:error, "Pregunta #{numero}: #{detalle}"}
            end

          error -> error
        end
      end)

    case revision do
      :ok ->
        case validar_repetidas(preguntas) do
          :ok -> validar_cantidades(preguntas)
          error -> error
        end

      error -> error
    end
  end

  defp validar_repetidas(preguntas) do
    preguntas
    |> Enum.with_index(1)
    |> Enum.reduce({:ok, []}, fn {pregunta, numero}, resultado ->
      case resultado do
        {:error, _} -> resultado
        {:ok, anteriores} ->
          repetida = Enum.any?(anteriores, fn previa ->
            previa["tema"] == pregunta["tema"] and previa["enunciado"] == pregunta["enunciado"]
          end)

          if repetida do
            {:error, "Pregunta #{numero}: enunciado repetido en #{pregunta["tema"]}"}
          else
            {:ok, [pregunta | anteriores]}
          end
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp validar_pregunta(pregunta) when not is_map(pregunta),
    do: {:error, "debe ser un objeto JSON"}

  defp validar_pregunta(pregunta) do
    tema = pregunta["tema"]
    nivel = pregunta["nivel"]
    enunciado = pregunta["enunciado"]
    opciones = pregunta["opciones"]
    respuesta = pregunta["respuesta"]

    cond do
      not is_binary(tema) or String.trim(tema) == "" or
          String.downcase(tema) != tema or String.split(tema) != [tema] ->
        {:error, "tema inválido"}

      nivel not in ["basico", "intermedio", "avanzado"] ->
        {:error, "nivel inválido"}

      not is_binary(enunciado) or String.trim(enunciado) == "" ->
        {:error, "enunciado vacío"}

      not is_map(opciones) or Map.keys(opciones) |> Enum.sort() != ["A", "B", "C", "D"] ->
        {:error, "debe tener exactamente las opciones A, B, C y D"}

      not Enum.all?(Map.values(opciones), fn texto ->
        is_binary(texto) and String.trim(texto) != ""
      end) ->
        {:error, "una opción está vacía"}

      length(Enum.uniq(Map.values(opciones))) != 4 ->
        {:error, "hay opciones repetidas"}

      respuesta not in ["A", "B", "C", "D"] ->
        {:error, "respuesta correcta inválida"}

      true -> :ok
    end
  end

  defp validar_cantidades(preguntas) do
    temas = preguntas |> Enum.map(fn p -> p["tema"] end) |> Enum.uniq()

    cond do
      length(temas) < 4 ->
        {:error, "El banco debe tener al menos cuatro temas"}

      true ->
        Enum.reduce(temas, :ok, fn tema, resultado ->
          case resultado do
            {:error, _} -> resultado
            :ok ->
              faltante = Enum.find(["basico", "intermedio", "avanzado"], fn nivel ->
                Enum.count(preguntas, fn p -> p["tema"] == tema and p["nivel"] == nivel end) < 8
              end)

              if faltante do
                {:error, "Tema #{tema}, nivel #{faltante}: se requieren ocho preguntas"}
              else
                :ok
              end
          end
        end)
    end
  end

  def handle_call(:temas, _desde, preguntas) do
    {:reply, preguntas |> Enum.map(&Map.get(&1, "tema")) |> Enum.uniq(), preguntas}
  end

  def handle_call({:disponibles, tema, nivel, total}, _desde, preguntas) do
    {:reply, comprobar(preguntas, tema, nivel, total), preguntas}
  end

  def handle_call({:seleccionar, tema, nivel, total}, _desde, preguntas) do
    resultado =
      case comprobar(preguntas, tema, nivel, total) do
        :ok ->
          reparto = Trivia.Nivel.reparto(nivel, total)
          elegidas = Enum.flat_map(["basico", "intermedio", "avanzado"], fn dificultad ->
            preguntas
            |> Enum.filter(fn p -> p["tema"] == tema and p["nivel"] == dificultad end)
            |> Enum.shuffle()
            |> Enum.take(Map.get(reparto, dificultad))
          end)
          {:ok, elegidas}

        error -> error
      end

    {:reply, resultado, preguntas}
  end

  defp comprobar(_preguntas, _tema, _nivel, total) when not is_integer(total) or total < 1 do
    {:error, "La cantidad de preguntas debe ser positiva"}
  end

  defp comprobar(preguntas, tema, nivel, total) do
    if not Enum.any?(preguntas, fn p -> p["tema"] == tema end) do
      {:error, "Tema inexistente: #{tema}"}
    else
      reparto = Trivia.Nivel.reparto(nivel, total)

      faltan = Enum.any?(reparto, fn {dificultad, cantidad} ->
        disponibles = Enum.count(preguntas, fn p -> p["tema"] == tema and p["nivel"] == dificultad end)
        disponibles < cantidad
      end)

      if faltan, do: {:error, "No hay suficientes preguntas para el reparto"}, else: :ok
    end
  end
end


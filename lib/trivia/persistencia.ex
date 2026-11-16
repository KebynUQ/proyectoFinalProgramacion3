defmodule Trivia.Persistencia do
  @moduledoc "Único proceso responsable de modificar usuarios e historial."
  use GenServer

  def start_link(_argumentos \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar(usuario, clave), do: GenServer.call(__MODULE__, {:registrar, usuario, clave})
  def historial, do: GenServer.call(__MODULE__, :historial)
  def guardar_resultado(resultado), do: GenServer.call(__MODULE__, {:guardar, resultado})
  def siguiente_id, do: GenServer.call(__MODULE__, :siguiente_id)

  def init(:ok) do
    carpeta = Path.join(File.cwd!(), "data")
    File.mkdir_p!(carpeta)
    usuarios = Path.join(carpeta, "users.json")
    resultados = Path.join(carpeta, "results.log")
    contador = Path.join(carpeta, "last_game_id.txt")
    unless File.exists?(usuarios), do: File.write!(usuarios, "{}\n")
    unless File.exists?(resultados), do: File.write!(resultados, "")
    {:ok, contenido} = File.read(usuarios)

    with {:ok, mapa} when is_map(mapa) <- Jason.decode(contenido),
         {:ok, registros} <- leer_historial(resultados),
         {:ok, ultimo} <- leer_contador(contador, registros) do
      {:ok,
       %{
         usuarios: mapa,
         archivo_usuarios: usuarios,
         archivo_resultados: resultados,
         archivo_contador: contador,
         ultimo_id: ultimo
       }}
    else
      error -> {:stop, {:datos_invalidos, error}}
    end
  end

  def handle_call({:registrar, usuario, clave}, _desde, estado) do
    case Map.fetch(estado.usuarios, usuario) do
      {:ok, ^clave} ->
        {:reply, {:ok, :existente}, estado}

      {:ok, _otra} ->
        {:reply, {:error, "Clave incorrecta"}, estado}

      :error ->
        nuevos = Map.put(estado.usuarios, usuario, clave)

        case File.write(estado.archivo_usuarios, Jason.encode!(nuevos)) do
          :ok ->
            {:reply, {:ok, :nuevo}, %{estado | usuarios: nuevos}}

          {:error, motivo} ->
            {:reply, {:error, "No se pudo guardar usuario: #{inspect(motivo)}"}, estado}
        end
    end
  end

  def handle_call(:historial, _desde, estado) do
    {:reply, leer_historial(estado.archivo_resultados), estado}
  end

  def handle_call(:siguiente_id, _desde, estado) do
    siguiente = estado.ultimo_id + 1

    case File.write(estado.archivo_contador, Integer.to_string(siguiente)) do
      :ok ->
        {:reply, {:ok, "P-#{siguiente}"}, %{estado | ultimo_id: siguiente}}

      {:error, motivo} ->
        {:reply, {:error, "No se pudo reservar el ID de partida: #{inspect(motivo)}"}, estado}
    end
  end

  def handle_call({:guardar, resultado}, _desde, estado) do
    linea = Jason.encode!(resultado) <> "\n"
    {:reply, File.write(estado.archivo_resultados, linea, [:append]), estado}
  end

  defp leer_historial(ruta) do
    case File.open(ruta, [:read], fn archivo ->
           archivo
           |> IO.stream(:line)
           |> Enum.with_index(1)
           |> Enum.reduce({:ok, []}, fn {linea, numero}, resultado ->
             case resultado do
               {:error, _} ->
                 resultado

               {:ok, acumulado} ->
                 if String.trim(linea) == "" do
                   {:ok, acumulado}
                 else
                   case Jason.decode(linea) do
                     {:ok, registro} ->
                       if registro_valido?(registro) do
                         {:ok, [registro | acumulado]}
                       else
                         {:error, "Registro inválido en results.log, línea #{numero}"}
                       end

                     _ ->
                       {:error, "Registro inválido en results.log, línea #{numero}"}
                   end
                 end
             end
           end)
         end) do
      {:ok, {:ok, registros}} -> {:ok, Enum.reverse(registros)}
      {:ok, error} -> error
      {:error, motivo} -> {:error, "No se pudo leer results.log: #{inspect(motivo)}"}
    end
  end

  defp leer_contador(ruta, registros) do
    mayor_historial =
      registros
      |> Enum.map(fn registro -> numero_id(registro["id"]) end)
      |> Enum.max(fn -> 1000 end)

    case File.read(ruta) do
      {:ok, texto} ->
        case Integer.parse(String.trim(texto)) do
          {numero, ""} when numero >= 1000 -> {:ok, max(numero, mayor_historial)}
          _ -> {:error, "last_game_id.txt inválido"}
        end

      {:error, :enoent} ->
        {:ok, mayor_historial}

      {:error, motivo} ->
        {:error, "No se pudo leer last_game_id.txt: #{inspect(motivo)}"}
    end
  end

  defp numero_id("P-" <> numero) do
    case Integer.parse(numero) do
      {valor, ""} when valor >= 1001 -> valor
      _ -> :error
    end
  end

  defp numero_id(_), do: :error

  defp registro_valido?(%{
         "fecha" => fecha,
         "id" => id,
         "creador" => creador,
         "tema" => tema,
         "nivel" => nivel,
         "ganadores" => ganadores,
         "puntajes" => puntajes
       })
       when is_binary(fecha) and is_binary(id) and is_binary(creador) and
              is_binary(tema) and is_list(ganadores) and is_map(puntajes) do
    numero_id(id) != :error and
      fecha != "" and creador != "" and tema != "" and
      nivel in ["basico", "intermedio", "avanzado"] and
      map_size(puntajes) > 0 and
      Enum.all?(puntajes, fn {usuario, puntos} ->
        is_binary(usuario) and is_integer(puntos)
      end) and
      ganadores != [] and
      Enum.all?(ganadores, fn usuario ->
        is_binary(usuario) and Map.has_key?(puntajes, usuario)
      end)
  end

  defp registro_valido?(_), do: false
end

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
end

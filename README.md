# Toolkit CLI para JasperReports Server

Scripts `bash` + `curl` + `python3` para listar, importar (descargar) y exportar (subir) reportes (`.jrxml`) vía la API REST v2 de JasperReports Server (desarrollo por defecto), y abrirlos localmente en Jaspersoft Studio.

**Requisitos:** `bash`, `curl`, `python3` (Linux, Git Bash o WSL), o bien PowerShell 5.1+ en Windows (ver sección Windows). Jaspersoft Studio es opcional.

## Primeros pasos

```bash
./login.sh          # pide servidor, usuario y contraseña propios (no se guardan)
./test-conexion.sh  # verifica conexión y sesión
```
Configuración opcional: copiar `.env.example` a `.env`.

## Comandos

| Comando | Qué hace |
|---|---|
| `./login.sh` | Inicia sesión (cookie local, permisos 600) |
| `./logout.sh` | Cierra la sesión y borra la cookie |
| `./test-conexion.sh [--solo-alcance]` | Prueba alcance al servidor y sesión |
| `./listar.sh <carpeta> [--recursivo]` | Lista reportes de una carpeta |
| `./import-reporte.sh <uri> [-d <dir>]` | IMPORTA: descarga el reporte del servidor a `reportes/<uri>/` |
| `./export-reporte.sh <uri> <archivo.jrxml> [-y]` | EXPORTA: sube el `.jrxml` al servidor (hace respaldo en `backups/` antes, usando `import-reporte`) |
| `./abrir-studio.sh [archivo.jrxml]` | Abre Studio con los reportes locales (no usa el servidor) |

> **Semántica de nombres** (desde la perspectiva del equipo local): *importar* = traer el reporte del servidor al disco; *exportar* = publicar el `.jrxml` local en el servidor.

## Flujo de trabajo

1. `./login.sh`
2. `./import-reporte.sh /reports/carpeta/mi_reporte`
3. `./abrir-studio.sh reportes/reports/carpeta/mi_reporte/main_jrxml.jrxml` y editar; los guardados se reflejan en Studio.
4. Probar con la pestaña Preview de Studio.
5. `./export-reporte.sh /reports/carpeta/mi_reporte reportes/reports/carpeta/mi_reporte/main_jrxml.jrxml`

## Jaspersoft Studio

- Una sola vez: `File > Import > General > Existing Projects into Workspace`, elegir `~/JaspersoftWorkspace`, marcar `toolkit-jasper` (sin copiar). Si no ves los cambios, `F5` sobre el proyecto.
- Preview con datos: crear un Data Adapter "Database JDBC Connection" (driver `oracle.jdbc.OracleDriver`, URL `jdbc:oracle:thin:@//HOST:PUERTO/SERVICIO`, usuario y contraseña propios) y agregar el `.jar` de `ojdbc` en `Driver Classpath` (Studio no lo incluye).
- Si Studio no se encuentra: definir `STUDIO_BIN=/ruta/al/ejecutable`.

## Windows (.bat / .ps1)

Cada script `.sh` tiene su equivalente `.ps1` (PowerShell 5.1+, sin `bash`/`curl`/`python3`; la lógica común está en `lib/JasperApi.psm1`) y un wrapper `.bat` homónimo que ejecuta el `.ps1` con `powershell -NoProfile -ExecutionPolicy Bypass` y propaga el código de salida. Se pueden usar con doble clic (pausa al final) o desde `cmd`/PowerShell, sin cambiar la ExecutionPolicy:

| Comando Windows | Equivale a |
|---|---|
| `login.bat` | `./login.sh` |
| `logout.bat` | `./logout.sh` |
| `test-conexion.bat [--solo-alcance]` | `./test-conexion.sh` |
| `listar.bat <carpeta> [--recursivo]` | `./listar.sh` |
| `import-reporte.bat <uri> [-d <dir>]` | `./import-reporte.sh` (descarga del servidor) |
| `export-reporte.bat <uri> <archivo.jrxml> [-y]` | `./export-reporte.sh` (sube al servidor, con respaldo) |
| `abrir-studio.bat [archivo.jrxml]` | `./abrir-studio.sh` |

`abrir-studio` busca Studio en `C:\Program Files\TIBCO\Jaspersoft Studio*`, `C:\Program Files\Jaspersoft\Jaspersoft Studio*` y `%LOCALAPPDATA%`. Overrides: `STUDIO_BIN` (ejecutable) y `STUDIO_WORKSPACE` (default `%USERPROFILE%\JaspersoftWorkspace`); si no lo encuentra, pide definir `STUDIO_BIN`. Configuración (`.env`), cookie `.jasper-session` y carpetas `reportes/` y `backups/` son las mismas que en Linux.

# Truenito

App para la barra de menú de macOS que te avisa cuando el Servicio Meteorológico Nacional (SMN) emite una alerta o un aviso a corto plazo que cubre tu ciudad. Además te muestra en qué horarios conviene tener más cuidado.

> App no oficial, hecha por un particular. No está asociada al SMN.

## Instalar

1. Bajá el zip de la [última versión](https://github.com/jlgasparrini/truenito/releases/latest) y descomprimilo.
2. Abrí la app. Si la abrís desde Descargas, te ofrece moverse a Aplicaciones; aceptá, así puede actualizarse sola.
3. La primera vez, macOS puede decir que no puede verificar al desarrollador, porque la app no está firmada con una cuenta paga de Apple. Abrila con clic derecho → **Abrir**, o desde Configuración del Sistema → Privacidad y seguridad → **Abrir igualmente**.
4. Elegí tu ciudad y permití las notificaciones.

Necesita macOS 13 o superior. Funciona en Mac con Intel y con Apple silicon.

## Qué hace

- **Avisa las alertas del SMN** que cubren tus ciudades, una sola vez por fenómeno. Vuelve a avisar si sube el nivel, una hora antes de que empeore ("Tormentas: pasa a naranja a las 02:10") y cuando termina.
- **Ícono en la barra:** el fenómeno (tormenta, lluvia, viento, nieve) con un punto 🟡🟠🔴. Cuando llega algo nuevo, el punto parpadea y suena hasta que abrís el panel: Ping (amarilla), Hero (naranja) o Sosumi ×3 (roja). El sonido se corta solo a los 2 minutos.
- **Panel:** el clima de ahora (tocalo y se abre la app Tiempo de Apple), una fila por fenómeno con su evolución ("Amarilla hasta las 20:59 · luego naranja"), los detalles y recomendaciones del SMN, y un gráfico de lluvia de las próximas 24 h con las horas de más cuidado.
- **Notificación** con dos botones: **Ver detalles** abre el panel y **Silenciar** corta el parpadeo y el sonido.
- **Ajustes:** varias ciudades, desde qué nivel avisar, sonido, silencio de las amarillas a la noche, temperatura en la barra, apariencia clara u oscura, abrir al iniciar sesión y actualizaciones automáticas.

## Privacidad y consumo

La app no tiene cuentas, publicidad ni analíticas. Solo se conecta con:

- **SMN** (`ssl.smn.gob.ar`): el feed de alertas, cada 5 minutos.
- **Open-Meteo** (`open-meteo.com`): el clima cada 15 minutos, el pronóstico por hora solo mientras hay una alerta, y la búsqueda de ciudades. Recibe las coordenadas de tus ciudades.
- **GitHub**: una vez por día, para ver si hay una versión nueva (se puede apagar).

Usa unos 35 MB de memoria y casi nada de CPU. Los archivos de alertas se guardan en `~/Library/Application Support/Truenito` (menos de 1 MB) para no volver a bajarlos.

## Cómo funciona

- **Alertas:** el SMN publica sus alertas en formato [CAP](https://es.wikipedia.org/wiki/Common_Alerting_Protocol), el estándar internacional, en `https://ssl.smn.gob.ar/CAP/AR.php`. Cada alerta trae polígonos, severidad y vigencia; la app revisa si tu ciudad cae dentro de algún polígono.
- **Límite del SMN:** permite 180 descargas de XML cada 10 minutos. La app baja como máximo 80 por consulta, primero los avisos a corto plazo y después los de tu región, así que la primera carga completa puede tardar unos 10 minutos.
- **Sin avisos repetidos:** el SMN reemite cada alerta con un identificador nuevo en cada actualización, así que la app recuerda qué fenómeno y qué nivel ya te avisó.
- **Horarios de cuidado:** del pronóstico por hora de Open-Meteo marca tormenta (códigos WMO 95–99), lluvia de 2 mm/h o más, ráfagas de 50 km/h o más y nieve.

## Desarrollo

Necesita las Command Line Tools de Xcode (no hace falta Xcode).

```sh
swift test                      # tests de la lógica, sin red
./build-app.sh 1.0.0 --dev      # app de desarrollo en build/
open "build/Truenito.app"
./smoke-test.sh                 # abre la app compilada y verifica que consulta al SMN
```

El build de desarrollo agrega **Probar estados** en el menú ··· del panel, que simula cada caso sin consultar al SMN. También genera capturas de cada estado en modo claro y oscuro:

```sh
"build/Truenito.app/Contents/MacOS/Truenito" --snapshots /tmp/capturas
```

Estructura:

- `Sources/SMNCore`: la lógica, sin interfaz y con tests: parser CAP, reglas de aviso, pronóstico y `AlertMonitor`, que consulta al SMN. La red y el disco se inyectan.
- `Sources/Truenito`: la app (AppKit + SwiftUI). `AppModel` es la única fuente de estado.
- `scripts/make-icon.swift`: dibuja el ícono y regenera `Resources/AppIcon.icns`.

Swift 6 con chequeo estricto de concurrencia. La única dependencia es [Sparkle](https://sparkle-project.org), para las actualizaciones. Las pautas para colaborar (también para agentes de IA) están en [AGENTS.md](AGENTS.md).

## Publicar una versión

1. `./build-app.sh X.Y.Z` genera el zip y `build/appcast.xml`, firmados con la clave EdDSA guardada en el Llavero (cuenta `smn-alertas`).
2. Crear la release `vX.Y.Z` en GitHub y subir **los dos** archivos.

Las copias instaladas leen `appcast.xml` de la última release. Si se pierde la clave privada ya no aceptan actualizaciones: hacé un respaldo con `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account smn-alertas -x clave.txt` y guardalo fuera del repo.

## Créditos y licencia

- Alertas: [Servicio Meteorológico Nacional](https://www.smn.gob.ar).
- Clima, pronóstico y búsqueda de ciudades: [Open-Meteo](https://open-meteo.com), con licencia [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- Actualizaciones: [Sparkle](https://sparkle-project.org) (MIT).

Código bajo licencia [MIT](LICENSE).

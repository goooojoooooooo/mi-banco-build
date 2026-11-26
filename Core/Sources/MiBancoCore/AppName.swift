/// El nombre de la app que ve el dueño (debajo del icono, en Atajos, en la guía, en los avisos). Un solo sitio para todos
/// los objetivos: la app lo lee por `AppIdentity.displayName` y la guía por `guideAppName`. `CFBundleDisplayName` de
/// `project.yml` tiene que decir lo mismo (lo comprueba `tools/check_gates.sh`). Los identificadores (`com.mibanco…`,
/// el esquema `mibanco`, el grupo compartido, el Llavero, los ficheros) NO cambian con el nombre.
public let appDisplayName = "Onyx"

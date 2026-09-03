import unreal


def main():
    exporter = getattr(unreal, "GLTFExporter", None)
    options = getattr(unreal, "GLTFExportOptions", None)
    unreal.log("SOCOM_GLTF_PROBE exporter={}".format(exporter))
    unreal.log("SOCOM_GLTF_PROBE options={}".format(options))
    if exporter is None or options is None:
        raise RuntimeError("GLTFExporter plugin is not available")
    unreal.log("SOCOM_GLTF_PROBE methods={}".format(sorted(dir(exporter))))


main()

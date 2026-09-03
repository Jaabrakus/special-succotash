FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.1
ARG GODOT_RELEASE=stable
ARG GODOT_LINUX_SHA256=c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl unzip libfontconfig1 \
    && curl --fail --location --show-error \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip" \
        --output /tmp/godot.zip \
    && echo "${GODOT_LINUX_SHA256}  /tmp/godot.zip" | sha256sum --check --strict \
    && unzip -q /tmp/godot.zip -d /opt/godot \
    && mv "/opt/godot/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64" /opt/godot/godot \
    && chmod 0755 /opt/godot/godot \
    && useradd --create-home --uid 10001 socom \
    && rm -f /tmp/godot.zip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/socom
COPY --chown=socom:socom . /srv/socom

# The production image never opens the editor. Remove only the copied
# editor-plugin block so headless import does not try to load authoring tools
# that are intentionally excluded from the narrow server build context.
RUN sed -i '/^\[editor_plugins\]$/,/^$/d' /srv/socom/project.godot \
    && chmod 0755 /srv/socom/deploy/server/start_server.sh \
    && install -d --owner=socom --group=socom /srv/socom/.godot

USER socom

# Import once in the image so a production restart does not rebuild the Godot
# cache before it can bind Render's public WebSocket port.
RUN /opt/godot/godot \
    --headless \
    --recovery-mode \
    --path /srv/socom \
    --log-file /tmp/socom-godot-import.log \
    --import

EXPOSE 10000

ENTRYPOINT ["/srv/socom/deploy/server/start_server.sh"]

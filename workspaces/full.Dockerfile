#--------------------------------------------------------------------------
# Full Development Workspace (Pre-installed Languages)
#--------------------------------------------------------------------------
# 此镜像继承自 base，在构建时预装常用语言运行时。
# 适合希望首次启动无需等待语言下载的场景。
# 用法:
#   docker build --build-arg LANGUAGES="go@1.22.4 rust@stable php@8.3.6" -f workspaces/full.Dockerfile workspaces/
#--------------------------------------------------------------------------

ARG WORKSPACE_BASE_TAG=latest
FROM development-docker-workspace-base:${WORKSPACE_BASE_TAG}

LABEL maintainer="muxk <361087696@qq.com>"
LABEL description="Full development workspace with pre-installed languages via mise"

USER root

ARG LANGUAGES=""
ARG WORKSPACE_USER=developer
ARG WORKSPACE_HOME=/home/developer

# Ensure mise is available for subsequent RUN commands
ENV PATH="/usr/local/bin:${PATH}"

###########################################################################
# Pre-install languages via mise (optional, at build time)
###########################################################################

RUN if [ -n "${LANGUAGES}" ]; then \
    su - ${WORKSPACE_USER} -c "export PATH=\"/usr/local/bin:\${PATH}\" && mise install ${LANGUAGES}" \
    && su - ${WORKSPACE_USER} -c "export PATH=\"/usr/local/bin:\${PATH}\" && mise reshim"; \
    fi

###########################################################################
# Final
###########################################################################

RUN chown -R ${WORKSPACE_USER}:${WORKSPACE_USER} ${WORKSPACE_HOME}

USER ${WORKSPACE_USER}
WORKDIR ${WORKSPACE_HOME}

CMD ["sleep", "infinity"]

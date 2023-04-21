#
#--------------------------------------------------------------------------
# Image Setup
#--------------------------------------------------------------------------

FROM golang:${GOLANG_VERSION}

LABEL maintainer="muxk <361087696@qq.com>"

# Set Environment Variables
ENV DEBIAN_FRONTEND noninteractive

ENV GO111MODULE=on \
    GOPROXY="https://goproxy.cn,direct"

# Start as root
USER root

###########################################################################
# Set Timezone
###########################################################################

ARG TZ=UTC
ENV TZ ${TZ}

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

###########################################################################
# DNS utilities:
###########################################################################

ARG INSTALL_DNSUTILS=false

RUN if [ ${INSTALL_DNSUTILS} = true ]; then \
    apt-get update && apt-get upgrade -y && apt-get autoremove && apt-get install -y dnsutils \
;fi

###########################################################################
# zsh
###########################################################################

RUN apt-get update && apt-get install -y vim \
zsh \
zsh-syntax-highlighting \
screen
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --keep-zshrc"
RUN echo "source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> /root/.zshrc
RUN chsh -s /bin/zsh
RUN /bin/zsh -c "source /root/.zshrc"

###########################################################################
# goctl
###########################################################################

RUN go install github.com/zeromicro/go-zero/tools/goctl@latest

###########################################################################
# protoc & protoc-gen-go
###########################################################################

RUN goctl env check -i -f --verbose

###########################################################################
# ssh:
###########################################################################

ARG INSTALL_WORKSPACE_SSH=false

COPY insecure_id_rsa /tmp/id_rsa
COPY insecure_id_rsa.pub /tmp/id_rsa.pub

RUN if [ ${INSTALL_WORKSPACE_SSH} = true ]; then \
    mkdir -p /root/.ssh \
    && rm -f /etc/service/sshd/down && \
    cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys \
        && cat /tmp/id_rsa.pub >> /root/.ssh/id_rsa.pub \
        && cat /tmp/id_rsa >> /root/.ssh/id_rsa \
        && rm -f /tmp/id_rsa* \
        && chmod 644 /root/.ssh/authorized_keys /root/.ssh/id_rsa.pub \
    && chmod 400 /root/.ssh/id_rsa \
;fi

#
#--------------------------------------------------------------------------
# Final Touch
#--------------------------------------------------------------------------
#

# Clean up
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    rm /var/log/lastlog /var/log/faillog

# Set default work directory
WORKDIR /go/src

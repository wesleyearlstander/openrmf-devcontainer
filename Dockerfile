ARG BASE_IMAGE=ubuntu:jammy


# Supports microdnf
FROM maven:3.8.3-openjdk-16 AS xsdcache

# Schema set up for autocompletion on files (Add as required)

# Install schema-fetcher
RUN microdnf install git && \
    git clone --depth=1 https://github.com/mfalaize/schema-fetcher.git && \
    cd schema-fetcher && \
    mvn install

# Fetch XSD file for package.xml
RUN mkdir -p /opt/xsd/package.xml && \
    java -jar schema-fetcher/target/schema-fetcher-1.0.0-SNAPSHOT.jar /opt/xsd/package.xml http://download.ros.org/schema/package_format2.xsd

# Fetch XSD file for roslaunch
RUN mkdir -p /opt/xsd/roslaunch && \
    java -jar schema-fetcher/target/schema-fetcher-1.0.0-SNAPSHOT.jar /opt/xsd/roslaunch https://gist.githubusercontent.com/nalt/dfa2abc9d2e3ae4feb82ca5608090387/raw/roslaunch.xsd

# Fetch XSD files for SDFormat (Simulation Description Format)
RUN mkdir -p /opt/xsd/sdf && \
    java -jar schema-fetcher/target/schema-fetcher-1.0.0-SNAPSHOT.jar /opt/xsd/sdf http://sdformat.org/schemas/root.xsd && \
    sed -i 's|http://sdformat.org/schemas/||g' /opt/xsd/sdf/*

# Fetch XSD file for URDF (Unified Robot Description Format)
RUN mkdir -p /opt/xsd/urdf && \
    java -jar schema-fetcher/target/schema-fetcher-1.0.0-SNAPSHOT.jar /opt/xsd/urdf https://raw.githubusercontent.com/devrt/urdfdom/xsd-with-xacro/xsd/urdf.xsd

FROM $BASE_IMAGE

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND noninteractive
ENV ROS_DISTRO humble

# workaround to enable bash completion for apt-get
# see: https://github.com/tianon/docker-brew-ubuntu-core/issues/75
RUN rm /etc/apt/apt.conf.d/docker-clean

# Ensure UTF-8 locale
RUN apt update && apt install locales
RUN locale-gen en_US en_US.UTF-8
RUN update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
RUN export LANG=en_US.UTF-8

# Enable Ubuntu Universe Repository
RUN apt install -y software-properties-common
RUN add-apt-repository universe

# Install certificate transport layers
RUN apt-get update || true && \
    apt-get install -y curl apt-transport-https ca-certificates && \
    apt-get clean

# Add the ROS 2 GPG key with apt
RUN apt update && apt install curl -y
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg

# Add the repository to the sources list
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null

# OSRF distribution is better for gazebo
RUN sh -c 'echo "deb http://packages.osrfoundation.org/gazebo/ubuntu-stable `lsb_release -cs` main" > /etc/apt/sources.list.d/gazebo-stable.list' && \
    curl -L http://packages.osrfoundation.org/gazebo.key | apt-key add -

# nice to have nodejs for web goodies
RUN sh -c 'echo "deb https://deb.nodesource.com/node_16.x `lsb_release -cs` main" > /etc/apt/sources.list.d/nodesource.list' && \
    curl -sSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -

# install depending packages
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y bash-completion less wget vim-tiny iputils-ping net-tools openssh-client git openjdk-8-jdk-headless nodejs sudo imagemagick byzanz python3-dev build-essential libsecret-1-dev && \
    npm install -g yarn && \
    apt-get clean

# basic python packages
RUN apt-get install -y python-is-python3; \
    curl -kL https://bootstrap.pypa.io/get-pip.py | python; \
    pip install --upgrade --ignore-installed --no-cache-dir pyassimp pylint==1.9.4 autopep8 python-language-server[all] notebook~=5.7 Pygments matplotlib ipywidgets jupyter_contrib_nbextensions nbimporter supervisor supervisor_twiddler argcomplete

# jupyter extensions
RUN jupyter nbextension enable --py widgetsnbextension && \
    jupyter contrib nbextension install --system

# add non-root user
RUN useradd -m developer && \
    echo developer ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/developer && \
    chmod 0440 /etc/sudoers.d/developer

# install depending packages (install moveit! algorithms on the workspace side, since moveit-commander loads it from the workspace)
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y ros-$ROS_DISTRO-desktop ros-$ROS_DISTRO-ros-base ros-dev-tools ros-$ROS_DISTRO-moveit ros-$ROS_DISTRO-moveit-ros-visualization && \
    apt-get clean

# configure services
RUN mkdir -p /etc/supervisor/conf.d
COPY .devcontainer/supervisord.conf /etc/supervisor/supervisord.conf
COPY .devcontainer/theia.conf /etc/supervisor/conf.d/theia.conf
COPY .devcontainer/jupyter.conf /etc/supervisor/conf.d/jupyter.conf

COPY .devcontainer/entrypoint.sh /entrypoint.sh

COPY .devcontainer/sim.py /usr/bin/sim

COPY --from=xsdcache /opt/xsd /opt/xsd

USER developer
WORKDIR /home/developer

ENV HOME /home/developer
ENV SHELL /bin/bash

# jre is required to use XML editor extension
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64

# colorize less
RUN echo "export LESS='-R'" >> ~/.bash_profile && \
    echo "export LESSOPEN='|pygmentize -g %s'" >> ~/.bash_profile

# enable bash completion
RUN git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it && \
    ~/.bash_it/install.sh --silent && \
    rm ~/.bashrc.bak && \
    echo "source /usr/share/bash-completion/bash_completion" >> ~/.bashrc && \
    bash -i -c "bash-it enable completion git"

RUN echo 'eval "$(register-python-argcomplete sim)"' >> ~/.bashrc

RUN git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && \
    ~/.fzf/install --all

RUN git clone --depth 1 https://github.com/b4b4r07/enhancd.git ~/.enhancd && \
    echo "source ~/.enhancd/init.sh" >> ~/.bashrc

# init rosdep
RUN sudo rosdep init
RUN rosdep update

# global vscode config
ADD .vscode /home/developer/.vscode
ADD .vscode /home/developer/.theia
ADD .devcontainer/compile_flags.txt /home/developer/compile_flags.txt
ADD .devcontainer/templates /home/developer/templates
RUN sudo chown -R developer:developer /home/developer

# install theia web IDE
COPY .devcontainer/theia-latest.package.json /home/developer/package.json
RUN sudo apt-get install -y libx11-dev libxkbfile-dev
RUN yarn --cache-folder ./ycache && rm -rf ./ycache && \
    NODE_OPTIONS="--max_old_space_size=4096" yarn theia build && \
    yarn theia download:plugins

ENV THEIA_DEFAULT_PLUGINS local-dir:/home/developer/plugins

# enable jupyter extensions
RUN jupyter nbextension enable hinterland/hinterland && \
    jupyter nbextension enable toc2/main && \
    jupyter nbextension enable code_prettify/autopep8 && \
    jupyter nbextension enable nbTranslate/main && \
    mkdir -p /home/developer/.ipython/profile_default && \
    echo "c.Completer.use_jedi = False" >> /home/developer/.ipython/profile_default/ipython_kernel_config.py

# enter ROS world
RUN echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> ~/.bashrc

EXPOSE 3000 8888

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "sudo", "-E", "/usr/local/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

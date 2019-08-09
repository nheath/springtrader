## Builder stage
FROM openjdk:7 as builder

WORKDIR /springtrader
COPY build.gradle gradle.properties settings.gradle gradlew ./
COPY .wrapper/ ./.wrapper
RUN ./gradlew build

COPY docs docs
COPY spring-nanotrader-asynch-services spring-nanotrader-asynch-services
COPY spring-nanotrader-chaos spring-nanotrader-chaos
COPY spring-nanotrader-data spring-nanotrader-data
COPY spring-nanotrader-service-support spring-nanotrader-service-support
COPY spring-nanotrader-services spring-nanotrader-services
COPY spring-nanotrader-web spring-nanotrader-web
COPY src src
COPY templates templates
COPY tools tools

RUN ./gradlew clean build release

## vFabric base stage
FROM centos:centos6 as vfabric
ENV JAVA_HOME=/usr

# Accept VMware certificate
RUN mkdir -p /etc/vmware/vfabric/ && \
    echo 'I_ACCEPT_EULA_LOCATED_AT=http://www.vmware.com/download/eula/vfabric_app-platform_eula.html' \
    > /etc/vmware/vfabric/accept-vfabric5.1-eula.txt

# Install vFabric software
RUN rpm -ivhf http://repo.vmware.com/pub/rhel6/vfabric/5.1/vfabric-5.1-repo-5.1-1.noarch.rpm && \
    yum install wget unzip java-1.7.0-openjdk-devel vfabric-tc-server-standard -y


## vFabric appserver stage
FROM vfabric as runner

# Install Groovy
WORKDIR /usr/bin
RUN wget http://dl.bintray.com/groovy/maven/groovy-binary-2.3.0-beta-2.zip
RUN unzip groovy-binary-2.3.0-beta-2.zip && \
    mv groovy-2.3.0-beta-2/bin/* . &&  \
    mv groovy-2.3.0-beta-2/* . && \
    rm -f groovy-binary-2.3.0-beta-2.zip

WORKDIR /app

# Add sqlfire client to data generation dependencies
COPY --from=builder /springtrader/dist/DataGenerator.zip .
RUN unzip DataGenerator.zip && \
    wget -P libs/ https://repo.spring.io/plugins-release/com/vmware/sqlfire/sqlfireclient/1.0.3/sqlfireclient-1.0.3.jar

# Copy template artifact to tc-server
COPY --from=builder /springtrader/templates/springtrader /opt/vmware/vfabric-tc-server-standard/templates/springtrader
RUN cp libs/sqlfireclient-1.0.3.jar /opt/vmware/vfabric-tc-server-standard/templates/springtrader/lib/sqlfireclient.jar

# Copy artifacts to server
WORKDIR /opt/vmware/vfabric-tc-server-standard
RUN ./tcruntime-instance.sh create springtrader -t springtrader -f templates/springtrader/sqlfire.properties
COPY --from=builder /springtrader/dist/spring-nanotrader-asynch-services-1.0.1.BUILD-SNAPSHOT.war springtrader/webapps/spring-nanotrader-asynch-services.war
COPY --from=builder /springtrader/dist/spring-nanotrader-services-1.0.1.BUILD-SNAPSHOT.war springtrader/webapps/spring-nanotrader-services.war
COPY --from=builder /springtrader/dist/spring-nanotrader-web-1.0.1.BUILD-SNAPSHOT.war springtrader/webapps/spring-nanotrader-web.war

WORKDIR /app

ENTRYPOINT /opt/vmware/vfabric-tc-server-standard/springtrader/bin/tcruntime-ctl.sh run springtrader

## SQLFire stage
FROM vfabric as sqlfdb
RUN yum install vfabric-sqlfire -y

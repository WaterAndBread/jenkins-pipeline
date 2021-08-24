#/bin/bash
app_name=${1:?}
env_name=${2:?}
jdk_version=${3:0}
now_date=$(date "+%Y%m%d_%H%M%S")
registry_url="xxx.xxx.com"

#git clone git@xxx.xxxx.com:xxxx/port-config.git
DICT_FILE=`cat ./port-config/dict.txt`

#DICT_FILE=`curl -s http://000.00.0.0:0000/dict.txt`
registry_project="public"
key=`echo $app_name|sed 's/-/_/g'`
PORT=`echo $DICT_FILE|jq ".${key}.port"`
deploy=${5:0}
webapp=`echo $DICT_FILE|jq ".${key}.webapp"`
script=`echo $DICT_FILE|jq ".${key}.script"`
script=`echo $script|sed 's/"//g'`

if [ $PORT == null ];then
        PORT=`echo $DICT_FILE|jq ".${key}.dubbo"`
fi

image_name=`echo ${app_name} | tr "[:upper:]" "[:lower:]"`

build_image_base_dir="/var/jenkins/build_images/public_${env_name}/${app_name}"
#new_image="${registry_url}/${registry_project}/${image_name}:${env_name}-${now_date}"
tnew_image=${4:0}
new_image=`echo ${tnew_image} | tr "[:upper:]" "[:lower:]"`
function log_time(){
        echo -n $(date "+%Y-%m-%d %H:%M:%S")
}

function exec_building_image(){
        echo "`log_time` [INFO] building image ${new_image} ..."
        docker build -t ${new_image} .
        if [ $? -eq 0 ];then
                echo "`log_time` [INFO] image build ${new_image} success"
                echo "`log_time` [INFO] pushing image ${new_image} ..."
                docker push ${new_image}
                docker rmi ${new_image}
                if [ $? -eq 0 ];then
                        echo "`log_time` [INFO] image push ${new_image} done"
                else
                        echo "`log_time` [INFO] image push ${new_image} failed"
                        exit 1
                fi
        else
                echo "`log_time` [ERROR] image build ${new_image} failed"
                exit 1
        fi



}

function gen_jar_service_entrypoint(){
app_base_dir="/app"
log_file="${app_base_dir}/${app_name}.log"
        cat > entrypoint.sh << EOF_ENTRYPOINT
#!/bin/bash

source ~/.bashrc

chmod +x ${app_base_dir}/${app_name}.jar

[ -f "${log_file}" ] || touch ${log_file}

exec java -jar \$JAVA_OPTS ${app_base_dir}/${app_name}.jar
EOF_ENTRYPOINT
chmod +x entrypoint.sh
}

function build_jar(){
        cd ${build_image_base_dir}
        gen_jar_service_entrypoint
        cat > Dockerfile << EOF_DOCKERFILE
FROM alpine:3.10
COPY entrypoint.sh /
COPY ${app_name}.jar /
EOF_DOCKERFILE

exec_building_image
}
function generate_serverxml(){
cat > server.xml << EOF_SERVERXML
<?xml version='1.0' encoding='utf-8'?>
<Server port="8005" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
  <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
  <Listener className="org.apache.catalina.core.JasperListener" />
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />
  <GlobalNamingResources>
    <Resource name="UserDatabase" auth="Container"
              type="org.apache.catalina.UserDatabase"
              description="User database that can be updated and saved"
              factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
              pathname="conf/tomcat-users.xml" />
  </GlobalNamingResources>
  <Service name="Catalina">
    <Connector port="${PORT}" URIEncoding="UTF-8" protocol="HTTP/1.1"
               connectionTimeout="20000"   maxKeepAliveRequests="1"
               redirectPort="8443"  bufferSize="8192" sockedBuffer="65536" 
                           acceptCount="200" maxThreads="500" maxSpareThreads="75" enableLookups="false"/>
    <Connector port="8009" protocol="AJP/1.3" redirectPort="8443" />

    <Engine name="Catalina" defaultHost="localhost">

      <Realm className="org.apache.catalina.realm.LockOutRealm">

        <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
               resourceName="UserDatabase"/>
      </Realm>

      <Host name="localhost"  appBase="webapps"
            unpackWARs="true" autoDeploy="true">

        <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="localhost_access_log." suffix=".txt"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />

      </Host>
    </Engine>
  </Service>
</Server>

EOF_SERVERXML

}

function build_tomcat(){
        cd ${build_image_base_dir}
        #log4j_jar_file="${build_image_base_dir}/${app_name}/${need_delete_log4j_jar}"
        generate_serverxml
        #[ -f "${log4j_jar_file}" ] && /bin/rm -f ${log4j_jar_file}
if  [ ${webapp}x =  '"ROOT"'x ]; then
        cat > Dockerfile << EOF_DOCKERFILE
FROM alpine:3.10
COPY server.xml /
COPY ${app_name}.war /ROOT.war
EOF_DOCKERFILE
else
       cat > Dockerfile << EOF_DOCKERFILE
FROM alpine:3.10
COPY ${app_name}.war /
COPY server.xml /
EOF_DOCKERFILE
fi
        exec_building_image
}

function shell_entrypoint(){
app_base_dir="/app/${app_name}"
log_file="${app_base_dir}/${app_name}.log"
        cat > entrypoint.sh << EOF_ENTRYPOINT
#!/bin/bash
source ~/.bashrc
/bin/bash /app/${app_name}/bin/${script} start
tail -f /app/${app_name}/log/*.log 
EOF_ENTRYPOINT
chmod +x entrypoint.sh
}



function build_shell(){
        cd ${build_image_base_dir}
chmod +x ${build_image_base_dir}/${app_name}/bin/*.sh
       shell_entrypoint
        cat > Dockerfile << EOF_DOCKERFILE
FROM alpine:3.10
COPY ${app_name} /${app_name}
COPY entrypoint.sh /entrypoint.sh
EOF_DOCKERFILE
        exec_building_image
}


#generate_nodejs_entrypoint
function generate_nodjs_entrypoint(){
        cd ${build_image_base_dir}
        cat > entrypoint.sh << EOF_ENTRYPOINT
for i in \`env | grep -E -i 'SERVICE|HOST|ADDR|PORT' | sed 's/=.*//'\` ; do unset \$i;done

exec pm2-docker start ecosystem.config.js --env production > /tmp/log


EOF_ENTRYPOINT
chmod +x entrypoint.sh

}


function build_nodejs(){
    cd ${build_image_base_dir}
    generate_nodjs_entrypoint
#if [ ${app_name} = "opm-web" ]; then
#    cat > Dockerfile << EOF_DOCKERFILE
#FROM node:10-alpine
#WORKDIR /${app_name}
#RUN yarn config set registry https://registry.npm.taobao.org
#RUN yarn config set sass_binary_site http://cdn.npm.taobao.org/dist/node-sass -g
#COPY entrypoint.sh /${app_name}
#ADD ${app_name}.tgz /${app_name}
#RUN yarn install
#RUN yarn add node-sass
#RUN yarn run build
#RUN yarn global add pm2
#CMD /bin/sh /${app_name}/entrypoint.sh
#EOF_DOCKERFILE

#else
        cat > Dockerfile << EOF_DOCKERFILE
FROM reg.ebanma.com/base/node:10.19.0-alpine
WORKDIR /${app_name}
COPY entrypoint.sh /${app_name}
ADD ${app_name}.tgz /${app_name}
RUN yarn install --production
CMD /bin/sh /${app_name}/entrypoint.sh

EOF_DOCKERFILE
#fi
exec_building_image


        }



echo $deploy
case "$deploy" in
          'war')

                  build_tomcat
            ;;
          'rwar')

                  build_tomcat
                        ;;
          'jar')

                  build_jar
            ;;
           'node')
   
                  build_nodejs
            ;;
           'shell')

                  build_shell
            ;;
           *)
            echo "the type of deployment is none"
           ;;
esac

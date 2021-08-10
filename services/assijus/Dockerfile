FROM jetty:9.3.9-jre8
MAINTAINER crivano@jfrj.jus.br

#--- DOWNLOAD LATEST VERSION FROM GITHUB
RUN curl -s https://api.github.com/repos/assijus/assijus/releases/latest \
  | grep browser_download_url \
  | grep assijus.war \
  | cut -d '"' -f 4 \
  | wget -qi -

#--- DEPLOY DO ARQUIVO .WAR ---
RUN mv assijus.war /var/lib/jetty/webapps/ 

# ADD deploy/assijus.war /var/lib/jetty/webapps/ 

EXPOSE 8080
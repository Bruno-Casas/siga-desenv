FROM jetty:9-jre8
MAINTAINER crivano@jfrj.jus.br

# DOWNLOAD LATEST VERSION FROM GITHUB
RUN curl -s https://api.github.com/repos/pmnams/blucservice/releases/latest \
  | grep browser_download_url \
  | grep blucservice.war \
  | cut -d '"' -f 4 \
  | wget -qi - \
  && mv blucservice.war /var/lib/jetty/webapps/

EXPOSE 8080

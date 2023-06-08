FROM jetty:9-jre8

# DOWNLOAD LATEST VERSION FROM GITHUB
RUN curl -s https://api.github.com/repos/pmnams/assijus/releases/latest \
  | grep browser_download_url \
  | grep assijus.war \
  | cut -d '"' -f 4 \
  | wget -qi - \
  && mv assijus.war /var/lib/jetty/webapps/

EXPOSE 8080
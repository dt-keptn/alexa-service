FROM ballerina/ballerina:0.991.0

COPY ./MANIFEST /
COPY ./alexa-service.balx /home/ballerina

RUN ls -la /

EXPOSE 8080

CMD ["sh", "-c", "cat /MANIFEST && ballerina run alexa-service.balx"]
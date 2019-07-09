import ballerina/http;
import ballerina/log;
import ballerina/io;
import ballerina/config;
import ballerina/test;

type KeptnData record {
    string image?;
    string tag?;
    string project?;
    string ^"service"?;
    string stage?;
    string State?;
    string ProblemID?;
    string ProblemTitle?;
    string ImpactedEntity?;
    KeptnEval evaluationdetails?;
    anydata...;
};

type KeptnEval record {
    string result?;
};

type KeptnEvent record {
    string specversion;
    string ^"type";
    string source?;
    string id?;
    string time?;
    string datacontenttype;
    string shkeptncontext;
    KeptnData data;
};

const NEW_ARTEFACT = "sh.keptn.events.new-artefact";
const CONFIGURATION_CHANGED = "sh.keptn.events.configuration-changed";
const DEPLOYMENT_FINISHED = "sh.keptn.events.deployment-finished";
const TESTS_FINISHED = "sh.keptn.events.tests-finished";
const EVALUATION_DONE = "sh.keptn.events.evaluation-done";
const PROBLEM = "sh.keptn.events.problem";
type KEPTN_EVENT NEW_ARTEFACT|CONFIGURATION_CHANGED|DEPLOYMENT_FINISHED|TESTS_FINISHED|EVALUATION_DONE|PROBLEM;
type KEPTN_CD_EVENT NEW_ARTEFACT|CONFIGURATION_CHANGED|DEPLOYMENT_FINISHED|TESTS_FINISHED|EVALUATION_DONE;

listener http:Listener alexaSubscriberEP = new(8080);

@http:ServiceConfig {
    basePath: "/"
}
service alexaservice on alexaSubscriberEP {
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/"
    }
    resource function handleEvent(http:Caller caller, http:Request request) {
        http:Client alexaEndpoint = new(getAlexaWebhookUrlHost());

        json|error payload = request.getJsonPayload();

        if (payload is error) {
            log:printError("error reading JSON payload", err = payload);
        }
        else {
            http:Request req = new;
            json alexaMessageJson = generateMessage(payload);
            req.setJsonPayload(alexaMessageJson);

            var response = alexaEndpoint->post(getAlexaWebhookUrlPath(), req);
            _ = handleResponse(response);
        }   

        http:Response res = new;
        checkpanic caller->respond(res);
    }
}

function getAlexaWebhookUrlHost() returns string {
    string alexaWebhookUrl = config:getAsString("ALEXA_WEBHOOK_URL");
    int indexOfServices = alexaWebhookUrl.indexOf("/v1");

    if (indexOfServices == -1) {
        error err = error("Environment variable ALEXA_WEBHOOK_URL is either missing or doesn't have the correct format.");
        panic err;
    }

    return alexaWebhookUrl.substring(0, indexOfServices);
}

function getAlexaWebhookUrlPath() returns string {
    string alexaWebhookUrl = config:getAsString("ALEXA_WEBHOOK_URL");
    int indexOfServices = alexaWebhookUrl.indexOf("/v1");
    return alexaWebhookUrl.substring(indexOfServices, alexaWebhookUrl.length());
}

function generateMessage(json payload) returns @untainted json {
    KeptnEvent|error event = KeptnEvent.convert(payload);

    if (event is error) {
        log:printError("error converting JSON payload '" + payload.toString() + "' to keptn event", err = event);
    }
    else {
        string text = "";
        string eventType = event.^"type";

        if (eventType is KEPTN_EVENT) {
            // new-artefact, configuration-changed, deployment-finished, tests-finished, evaluation-done
            if (eventType is KEPTN_CD_EVENT) {
                string knownEventType = getUpperCaseEventTypeFromEvent(event);
                text += "New Keptn event detected. ";
                text += knownEventType + "has been reported for the ";
                text += event.data.^"service" + " service in the ";
                text += event.data.project + " project.";
                // configuration-changed, deployment-finished, tests-finished, evaluation-done
                if (!(eventType is NEW_ARTEFACT)) {
                    text += "This was reported for stage " + event.data.stage + ". ";
                }
                if (eventType is EVALUATION_DONE) {
                    text += "The result of the evaluation was " + event.data.evaluationdetails.result + ". ";
                    if (event.data.evaluationdetails.result == "pass"){
                        text += "Promoting artifact from " + event.data.stage + "to next stage. ";
                    }
                }
            }
            // problem
            else {
                text += "New problem reported. P.I.D. " + event.data.ProblemID + ". " + event.data.ProblemTitle + "`\n";
                text += "The impact is " + event.data.ImpactedEntity + "`\n";
            }  
        }
        else {
            text += "*" + event.^"type".toUpper() + "*\n";
            text += "keptn can't process this event, the event type is unknown";
        }

        return generatealexaMessageJson(text, event);
    }
}

function getUpperCaseEventTypeFromEvent(KeptnEvent event) returns string {
    string eventType = event.^"type";
    int indexOfLastDot = eventType.lastIndexOf(".") + 1;
    eventType = eventType.substring(indexOfLastDot, eventType.length());
    eventType = eventType.replace("-", " ");
    return eventType.toUpper();
}

function generatealexaMessageJson(string text, KeptnEvent event) returns json {
    string accessCode = config:getAsString("ACCESS_CODE", defaultValue = "");
    json message = {
        text: text,
        blocks: [
                {
                    "notification": text,
                    "accessCode": accessCode,
                    "title": "Keptn Event"
                }
        ]
    };
    return message;
}

function getKeptnContext(KeptnEvent event) returns string {
    string template = "keptn-context: %s";
    string templateWithLink = "keptn-context: <%s|%s>";
    string url = config:getAsString("BRIDGE_URL", defaultValue = "");
    string keptnContext = "";

    if (url == "") {
        keptnContext = io:sprintf(template, event.shkeptncontext);
    }
    else {
        url += "/view-context/%s";
        string formattedURL = io:sprintf(url, event.shkeptncontext);
        keptnContext = io:sprintf(templateWithLink, formattedURL, event.shkeptncontext);
    }

    return keptnContext;
}

function handleResponse(http:Response|error response) {
    if (response is http:Response) {
        string|error res = response.getTextPayload();
        if (res is error) {
            io:println(res);
        }
        else {
            log:printInfo("event successfully sent to Alexa - response: " + res);
        }
    } else {
        io:println("Error when calling the backend: ", response.reason());
    }
}

// tests

@test:Config
function testGetUpperCaseEventTypeFromEvent() {
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "",
        data: {},
        ^"type": "something.bla.bla.new-artefact"
    };

    string eventType = getUpperCaseEventTypeFromEvent(event);
    test:assertEquals(eventType, "NEW ARTEFACT");
}

@test:Config
function testGeneratealexaMessageJson() {
    json expected = {
        text: "hello world",
        blocks: [
                {
                    "notification": "Hello World",
                    "accessCode": "accessCode",
                    "title": "Keptn Event"
                }
        ]
    };
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "12345",
        data: {},
        ^"type": "test-message"
    };
    json actual = generatealexaMessageJson("hello world", event);
    test:assertEquals(actual, expected);
}

@test:Config
function testGenerateMessageWithUnknownEventType() {
    string accessCode = config:getAsString("ACCESS_CODE", defaultValue = "");
    json expected = {
        text: "*COM.SOMETHING.EVENT*\nkeptn can't process this event, the event type is unknown",
        blocks: [
                {
                    "notification": "keptn can't process this event, the event type is unknown",
                    "accessCode": accessCode,
                    "title": "Keptn Event"
                }
        ]
    };
    json payload = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "123",
        data: {},
        ^"type": "com.something.event"
    };
    json actual = generateMessage(payload);
    test:assertEquals(actual, expected);
}

@test:Config
function testGetKeptnContextDefault() {
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "a9b94cff-1b10-4018-9b78-28898f78800d",
        data: {},
        ^"type": ""
    };
    string expected = "keptn-context: a9b94cff-1b10-4018-9b78-28898f78800d";
    string actual = getKeptnContext(event);
    test:assertEquals(actual, expected);
}

@test:Config{
    dependsOn: ["testGetKeptnContextDefault",
        "testGenerateMessageWithUnknownEventType",
        "testGeneratealexaMessageJson",
        "testGetUpperCaseEventTypeFromEvent"
    ]
}
function testGetKeptnContext() {
    config:setConfig("BRIDGE_URL", "https://www.google.at");
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "12345",
        data: {},
        ^"type": ""
    };
    string expected = "keptn-context: <https://www.google.at/view-context/12345|12345>";
    string actual = getKeptnContext(event);
    test:assertEquals(actual, expected);
}
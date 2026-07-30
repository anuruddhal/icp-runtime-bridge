// Copyright (c) 2026, WSO2 LLC. (http://wso2.com).
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ballerina/crypto;
import ballerina/file;
import ballerina/io;
import ballerina/jballerina.java;
import ballerina/log;
import ballerina/observe;
import ballerina/time;
import ballerina/uuid;

configurable string runtimeIdFile = ".icp_runtime_id";

// Initialize runtime ID once at module load time
final string currentRuntimeId = check initializeRuntimeId();
var _ = check observe:addTag("icp.runtimeId", currentRuntimeId);

// Initialize runtime ID - check if file exists, otherwise generate UUIDv4
isolated function initializeRuntimeId() returns string|error {
    // Use current working directory for the runtime ID file
    string runtimeIdPath = runtimeIdFile;

    // Check if file exists and read the persisted runtime ID
    if check file:test(runtimeIdPath, file:EXISTS) {
        string existingId = check io:fileReadString(runtimeIdPath);
        // Validate it's not empty and within valid length (max 100 chars)
        string trimmedId = existingId.trim();
        if trimmedId.length() > 0 && trimmedId.length() <= 100 {
            return trimmedId;
        }
    }

    // Generate a random UUIDv4
    string newRuntimeId = uuid:createRandomUuid().toString();

    // Ensure it doesn't exceed 100 characters
    if newRuntimeId.length() > 100 {
        newRuntimeId = newRuntimeId.substring(0, 100);
    }

    check io:fileWriteString(runtimeIdPath, newRuntimeId);
    return newRuntimeId;
}

isolated function getHeartbeat() returns Heartbeat|error {
    // First create heartbeat data without hash and timestamp
    HeartbeatForHash heartbeatForHash = {
        runtimeId: currentRuntimeId,
        runtimeType: BI,
        status: RUNNING,
        nodeInfo: check getBallerinaNode(),
        environment: environment,
        project: project,
        component: integration,
        artifacts: {
            listeners: check getListenerDetails(),
            services: check getServiceDetails(),
            main: check getMainArtifact()
        },
        logLevels: getLogLevels(),
        workflowCallbackUrl: enableWorkflowManagement? getWorkflowCallbackUrl() : (),
        tryItHost: getTryItHost()
    };

    // Add runtime only if not empty
    if runtime is string {
        heartbeatForHash.runtime = runtime;
    }

    // Calculate hash from the heartbeat content (excluding timestamp)
    string heartbeatContent = heartbeatForHash.toJsonString();
    string runtimeHash = calculateSimpleHash(heartbeatContent);

    // Create full heartbeat with hash and timestamp
    Heartbeat heartbeat = {
        runtimeId: heartbeatForHash.runtimeId,
        runtimeType: heartbeatForHash.runtimeType,
        status: heartbeatForHash.status,
        nodeInfo: heartbeatForHash.nodeInfo,
        environment: heartbeatForHash.environment,
        project: heartbeatForHash.project,
        component: heartbeatForHash.component,
        version: heartbeatForHash.version,
        artifacts: heartbeatForHash.artifacts,
        runtimeHash: runtimeHash,
        timestamp: time:utcNow(),
        logLevels: heartbeatForHash.logLevels,
        workflowCallbackUrl: heartbeatForHash?.workflowCallbackUrl,
        tryItHost: heartbeatForHash?.tryItHost
    };

    // Add runtime only if not empty
    if runtime is string {
        heartbeat.runtime = runtime;
    }

    // Add packed OpenAPI definitions only if there are any to send
    map<json> packedOpenApiDefinitions = getPackedOpenApiDefinitions();
    if packedOpenApiDefinitions.length() > 0 {
        heartbeat.openApiDefinitions = packedOpenApiDefinitions;
    }

    return heartbeat;
}

isolated function getLogLevels() returns map<log:Level> {
    log:LoggerRegistry registry = log:getLoggerRegistry();
    string[] ids = registry.getIds();
    map<log:Level> logLevels = {};
    foreach string id in ids {
        log:Logger? logger = registry.getById(id);
        if logger is log:Logger {
            logLevels[id] = logger.getLevel();
        }
    }
    return logLevels;
}

isolated function setLoggerLevel(string loggerId, log:Level logLevel) returns error? {
    log:LoggerRegistry registry = log:getLoggerRegistry();

    // Get the logger by ID
    log:Logger? logger = registry.getById(loggerId);
    if logger is () {
        return error(string `Logger not found for ID: ${loggerId}`);
    }

    check logger.setLevel(logLevel);
    log:printInfo(string `Set log level to ${logLevel} for logger: ${loggerId}`);
}

isolated function getDeltaHeartbeat(Heartbeat heartbeat) returns DeltaHeartbeat|error {
    DeltaHeartbeat deltaHeartbeat = {
        runtimeId: heartbeat.runtimeId,
        runtimeHash: heartbeat.runtimeHash,
        timestamp: time:utcNow()
    };
    return deltaHeartbeat;
}

isolated function calculateSimpleHash(string content) returns string {
    return crypto:hashMd5(content.toBytes()).toBase64();
}

isolated function getListenerDetails() returns ListenerDetail[]|error {
    Artifact[] artifacts = check getListeners();
    return artifacts.map(artifact => <ListenerDetail>check getDetailedArtifact(LISTENER, artifact.name));
}

isolated function getServiceDetails() returns ServiceDetail[]|error {
    Artifact[] artifacts = check getServices();
    return artifacts.map(artifact => <ServiceDetail>check getDetailedArtifact(SERVICE, artifact.name));
}

isolated function getServices() returns Artifact[]|error {
    Artifact[] artifacts = check getArtifacts(SERVICE, Artifact);
    return artifacts;
}

isolated function getListeners() returns Artifact[]|error {
    Artifact[] artifacts = check getArtifacts(LISTENER, Artifact);
    return artifacts;
}

isolated function getBallerinaNode() returns Node|error = @java:Method {
    'class: "io.ballerina.lib.wso2.icp.Utils"
} external;

isolated function getDetailedArtifact(string resourceType, string name) returns ArtifactDetail|error =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

isolated function getArtifacts(string resourceType, typedesc<anydata> t) returns Artifact[]|error =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

isolated function getMainArtifact() returns MainDetail?|error =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

// Strips trailing slashes and any path segment from the configured runtimeHostUrl, returning
// both the cleaned scheme+host[:port] and the bare authority (host[:port], no scheme) — shared
// by getWorkflowCallbackUrl (needs the scheme, to build a callable base URL) and getTryItHost
// (needs just the host, since the Try-It proxy already knows the target port separately).
isolated function getConfiguredHostUrl() returns [string, string] {
    string hostUrl = runtimeHostUrl.trim();
    // Strip trailing slashes to avoid a malformed "http://host/:port".
    while hostUrl.endsWith("/") {
        hostUrl = hostUrl.substring(0, hostUrl.length() - 1);
    }
    // Isolate the authority (host[:port]); anything before "://" is the scheme.
    int? schemeIndex = hostUrl.indexOf("://");
    int authorityStart = schemeIndex is int ? schemeIndex + 3 : 0;
    string authority = hostUrl.substring(authorityStart);
    int? pathIndex = authority.indexOf("/");
    if pathIndex is int {
        authority = authority.substring(0, pathIndex);
        hostUrl = hostUrl.substring(0, authorityStart) + authority;
    }
    return [hostUrl, authority];
}

isolated function getWorkflowCallbackUrl() returns string {
    var [hostUrl, authority] = getConfiguredHostUrl();
    // If runtimeHostUrl already includes a port, use it as-is rather than
    // appending the management port and producing "host:8080:9090".
    if authority.includes(":") {
        return hostUrl;
    }
    return string `${hostUrl}:${workflowManagementApiPort}`;
}

// Bare, reachable host/IP for this runtime (no scheme, no port) reported in every heartbeat so
// the ICP server can route Try-It proxy requests to it — the per-listener host captured
// separately (Listeners.java) is often a bind-all address like 0.0.0.0, not a usable target.
isolated function getTryItHost() returns string {
    var [_, authority] = getConfiguredHostUrl();
    int? portIndex = authority.indexOf(":");
    return portIndex is int ? authority.substring(0, portIndex) : authority;
}

isolated function stopListenerArtifact(string name) returns boolean|error =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

isolated function startListenerArtifact(string name) returns boolean|error =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

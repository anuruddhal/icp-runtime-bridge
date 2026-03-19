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

import ballerina/jwt;
import ballerina/log;

isolated function parseSecretWithKid(string secret) returns [string?, string] {
    int? periodIndex = secret.indexOf(".");
    if periodIndex is int && periodIndex > 0 {
        string kid = secret.substring(0, periodIndex);
        string keyMaterial = secret.substring(periodIndex + 1);
        log:printDebug(string `Parsed secret with kid: ${kid}, keyMaterial length: ${keyMaterial.length()}`);
        return [kid, keyMaterial];
    }
    return [(), secret];
}

final [string?, string] [kid, keyMaterial] = parseSecretWithKid(secret);

final readonly & jwt:IssuerSignatureConfig jwtSignatureConfig = {
    algorithm: jwt:HS256,
    config: keyMaterial
};

isolated function generateJwtToken() returns string|error {
    jwt:IssuerConfig issuerConfig = kid is string
        ? {
            issuer: jwtIssuer,
            audience: jwtAudience,
            customClaims: {"scope": "runtime_agent"},
            expTime: jwtExpiryTimeSeconds,
            signatureConfig: jwtSignatureConfig,
            keyId: kid
        }
        : {
            issuer: jwtIssuer,
            audience: jwtAudience,
            customClaims: {"scope": "runtime_agent"},
            expTime: jwtExpiryTimeSeconds,
            signatureConfig: jwtSignatureConfig
        };
    string token = check jwt:issue(issuerConfig);
    return token;
}

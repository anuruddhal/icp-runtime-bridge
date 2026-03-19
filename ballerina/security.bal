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

final [string, string] [keyId, keyMaterial] = check parseSecretWithKeyId(secret);

final readonly & jwt:IssuerSignatureConfig jwtSignatureConfig = {
    algorithm: jwt:HS256,
    config: keyMaterial
};

isolated function parseSecretWithKeyId(string secret) returns [string, string]|error {
    int? periodIndex = secret.indexOf(".");
    string keyId;
    string keyMaterial;

    if periodIndex is int && periodIndex > 0 {
        keyId = secret.substring(0, periodIndex);
        keyMaterial = secret.substring(periodIndex + 1);
    } else {
        keyId = "";
        keyMaterial = secret;
    }
    if keyMaterial.toBytes().length() < 32 {
        return error(string `Key material insufficient for HS256: ${keyMaterial.toBytes().length()} bytes (requires 32 bytes)`);
    }
    return [keyId, keyMaterial];
}

isolated function generateJwtToken() returns string|error {
    jwt:IssuerConfig issuerConfig = {
        issuer: jwtIssuer,
        audience: jwtAudience,
        customClaims: {"scope": "runtime_agent"},
        expTime: jwtExpiryTimeSeconds,
        signatureConfig: jwtSignatureConfig,
        keyId: keyId
    };
    string token = check jwt:issue(issuerConfig);
    return token;
}

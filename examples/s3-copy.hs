{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Lens
import Data.Aeson (Value (Array), object)
import qualified Data.ByteString.Lazy.Char8 as B
import Data.Text (Text)
import Stratosphere


main :: IO ()
main = B.putStrLn $ encodeTemplate myTemplate

myTemplate :: Template
myTemplate = template
  [ role, lambda, permission, incomingS3Bucket, outgoingS3Bucket ]
  & description ?~ "Simple event triggered S3 bucket to bucket copy example"
  & formatVersion ?~ "2010-09-09"

lambda :: Resource
lambda = (resource "CopyS3ObjectLambda" $
  LambdaFunctionProperties $
  lambdaFunction
    lambdaCode
    "index.handler"
    (GetAtt "IAMRole" "Arn")
    NodeJS43
    & lfFunctionName ?~ "copyS3Object"
  )
  & dependsOn ?~ [ role ^. resName ]

  where
    lambdaCode :: LambdaFunctionCode
    lambdaCode = lambdaFunctionCode
      & lfcZipFile ?~ code

    code :: Val Text
    code = "\
    \ var AWS = require('aws-sdk'); \
    \ var s3 = new AWS.S3({apiVersion: '2006-03-01'}); \
    \ exports.handler = function(event, context, callback) { \
    \  console.log(JSON.stringify(event)); \
    \  var rec = event.Records[0]; \
    \  var bucket = rec.s3.bucket.name; \
    \  var key = rec.s3.object.key; \
    \  s3.copyObject({Bucket: \"stratosphere-s3-copy-outgoing\", Key: key, CopySource: \"stratosphere-s3-copy-incoming/\"+key}, function(err){ \
    \    callback(null, \"copied s3 object\"); \
    \  }); \
    \ } \
    \ "


role :: Resource
role = resource "IAMRole" $
  IAMRoleProperties $
  iamRole rolePolicyDocumentObject
  & iamrPolicies ?~ [ executePolicy ]
  & iamrRoleName ?~ "MyLambdaBasicExecutionRole"
  & iamrPath ?~ "/"

  where
    executePolicy =
      iamPolicies
      [ ("Version", "2012-10-17")
      , ("Statement", statement)
      ] $
      "MyLambdaExecutionPolicy"

      where
        statement = object
          [ ("Effect", "Allow")
          , ("Action", actions)
          , ("Resource", "*")
          ]

        actions = Array
          [ "logs:CreateLogGroup"
          , "logs:CreateLogStream"
          , "logs:PutLogEvents"

          , "s3:PutObject"
          , "s3:GetObject"
          ]


    rolePolicyDocumentObject =
      [ ("Version", "2012-10-17")
      , ("Statement", statement)
      ]

      where
        statement = object
          [ ("Effect", "Allow")
          , ("Principal", principal)
          , ("Action", "sts:AssumeRole")
          ]

        principal = object
          [ ("Service", "lambda.amazonaws.com") ]

incomingS3Bucket :: Resource
incomingS3Bucket = (resource "IncomingBucket" $
  BucketProperties $
  bucket
    & bBucketName ?~ "stratosphere-s3-copy-incoming"
    & bNotificationConfiguration ?~ config
  )
  & dependsOn ?~ [ lambda ^. resName ]

  where
    config = s3NotificationConfiguration
      & sncLambdaConfigurations ?~ [lambdaConfig]

    lambdaConfig = s3NotificationConfigurationLambdaConfiguration
      "s3:ObjectCreated:*"
      (GetAtt "CopyS3ObjectLambda" "Arn")

outgoingS3Bucket :: Resource
outgoingS3Bucket = resource "OutgoingBucket" $
  BucketProperties $
  bucket
  & bBucketName ?~ "stratosphere-s3-copy-outgoing"


permission :: Resource
permission = resource "LambdaPermission" $
  LambdaPermissionProperties $
  lambdaPermission
    "lambda:*"
    (GetAtt "CopyS3ObjectLambda" "Arn")
    "s3.amazonaws.com"

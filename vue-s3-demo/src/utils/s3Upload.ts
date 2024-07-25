// s3Upload.ts
import { fromCognitoIdentityPool } from "@aws-sdk/credential-providers";
import type { Logger } from "@aws-sdk/types";
import {
  CreateMultipartUploadCommand,
  UploadPartCommand,
  CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand,
  S3Client,
  type CompletedPart,
} from "@aws-sdk/client-s3";

// Configuration constants
const CONFIG = {
  REGION: 'ap-southeast-1',
  BUCKET_NAME: "replace_your_bucket_name",
  IDENTITY_POOL_ID: 'ap-southeast-1:replace_your_identity_pool_id',
  PART_SIZE: 5 * 1024 * 1024, // 5MB parts
};

// Logger setup
const LOG_LEVEL = 'DEBUG'; // You can change this to 'INFO', 'WARN', or 'ERROR' as needed

const logger: Logger = {
  debug: (...args: any[]) => LOG_LEVEL === 'DEBUG' && console.debug('[S3 Upload Debug]', ...args),
  info: (...args: any[]) => ['DEBUG', 'INFO'].includes(LOG_LEVEL) && console.info('[S3 Upload Info]', ...args),
  warn: (...args: any[]) => ['DEBUG', 'INFO', 'WARN'].includes(LOG_LEVEL) && console.warn('[S3 Upload Warn]', ...args),
  error: (...args: any[]) => console.error('[S3 Upload Error]', ...args)
};

//Create S3 client
const s3Client = new S3Client({
  region: CONFIG.REGION,
  credentials: fromCognitoIdentityPool({
    clientConfig: { region: CONFIG.REGION },
    identityPoolId: CONFIG.IDENTITY_POOL_ID,
    logins: {}
  }),
  logger: logger
});
// const s3Client = new S3Client({
//     region: CONFIG.REGION,
//     credentials: ({
//       accessKeyId: 'replace_your_ak',
//       secretAccessKey: 'replace_your_sk'
//     }),
//     logger: logger
//   });

// Interface for upload result
interface UploadResult {
  success: boolean;
  message: string;
}

// Function to upload a part
async function uploadPart(file: File, uploadId: string, partNumber: number, start: number, end: number): Promise<CompletedPart> {
  logger.debug(`Uploading part ${partNumber}, start: ${start}, end: ${end}`);
  const part = file.slice(start, end);
  const response = await s3Client.send(
    new UploadPartCommand({
      Bucket: CONFIG.BUCKET_NAME,
      Key: file.name,
      UploadId: uploadId,
      Body: part,
      PartNumber: partNumber,
    })
  );
  logger.debug(`Part ${partNumber} uploaded successfully`);
  return {
    ETag: response.ETag,
    PartNumber: partNumber,
  };
}

// Main upload function
export async function uploadFileToS3(file: File): Promise<UploadResult> {
  let uploadId: string | undefined;

  try {
    logger.info(`Starting upload for file: ${file.name}, size: ${file.size} bytes`);

    // Initiate multipart upload
    const multipartUpload = await s3Client.send(
      new CreateMultipartUploadCommand({
        Bucket: CONFIG.BUCKET_NAME,
        Key: file.name,
      })
    );
    uploadId = multipartUpload.UploadId;
    logger.debug(`Multipart upload initiated with ID: ${uploadId}`);

    // Calculate parts
    const numParts = Math.ceil(file.size / CONFIG.PART_SIZE);
    logger.debug(`File will be uploaded in ${numParts} parts`);
    const uploadPromises: Promise<CompletedPart>[] = [];

    // Upload parts
    for (let i = 0; i < numParts; i++) {
      const start = i * CONFIG.PART_SIZE;
      const end = Math.min(start + CONFIG.PART_SIZE, file.size);
      uploadPromises.push(uploadPart(file, uploadId!, i + 1, start, end));
    }

    const completedParts = await Promise.all(uploadPromises);
    logger.debug(`All parts uploaded successfully`);

    // Complete multipart upload
    await s3Client.send(
      new CompleteMultipartUploadCommand({
        Bucket: CONFIG.BUCKET_NAME,
        Key: file.name,
        UploadId: uploadId,
        MultipartUpload: { Parts: completedParts },
      })
    );

    logger.info(`File ${file.name} uploaded successfully`);
    return { success: true, message: "File uploaded successfully" };
  } catch (err) {
    logger.error('Error during file upload:', err);

    // Abort multipart upload if it was initiated
    if (uploadId) {
      logger.warn(`Aborting multipart upload with ID: ${uploadId}`);
      await s3Client.send(
        new AbortMultipartUploadCommand({
          Bucket: CONFIG.BUCKET_NAME,
          Key: file.name,
          UploadId: uploadId,
        })
      );
    }

    return { success: false, message: "File upload failed" };
  }
}

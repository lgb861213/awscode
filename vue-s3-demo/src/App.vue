<template>
  <div>
    <input type="file" @change="handleFileUpload" />
    <button @click="uploadFile">Upload to S3</button>
    <p v-if="uploadStatus">{{ uploadStatus }}</p>
  </div>
</template>

<script lang="ts">
import { defineComponent, ref } from 'vue';
import { uploadFileToS3 } from '@/utils/s3Upload';

export default defineComponent({
  name: 'App',
  setup() {
    const selectedFile = ref<File | null>(null);
    const uploadStatus = ref<string>('');

    const handleFileUpload = (event: Event) => {
      const target = event.target as HTMLInputElement;
      if (target.files && target.files.length > 0) {
        selectedFile.value = target.files[0];
      }
    };

    const uploadFile = async () => {
      if (selectedFile.value) {
        uploadStatus.value = 'Uploading...';
        try {
          const result = await uploadFileToS3(selectedFile.value);
          uploadStatus.value = result.message;
        } catch (error) {
          uploadStatus.value = 'Upload failed: ' + (error as Error).message;
        }
      } else {
        uploadStatus.value = 'Please select a file first.';
      }
    };

    return {
      handleFileUpload,
      uploadFile,
      uploadStatus,
    };
  },
});
</script>

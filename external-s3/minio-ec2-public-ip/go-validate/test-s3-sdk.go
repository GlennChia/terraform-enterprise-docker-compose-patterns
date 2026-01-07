package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// TestResult represents the result of a test
type TestResult struct {
	Name   string
	Passed bool
}

// TestRunner manages S3 compatibility tests
type TestRunner struct {
	client     *s3.Client
	bucketName string
	results    []TestResult
}

func main() {
	// Get configuration from command line args or environment variables
	var endpointURL, accessKey, secretKey, bucketName string

	if len(os.Args) >= 4 {
		endpointURL = os.Args[1]
		accessKey = os.Args[2]
		secretKey = os.Args[3]
		if len(os.Args) >= 5 {
			bucketName = os.Args[4]
		}
	} else {
		endpointURL = os.Getenv("MINIO_ENDPOINT")
		accessKey = os.Getenv("MINIO_ACCESS_KEY")
		secretKey = os.Getenv("MINIO_SECRET_KEY")
		bucketName = os.Getenv("MINIO_TEST_BUCKET")
	}

	if bucketName == "" {
		bucketName = "sdk-test-bucket-go"
	}

	if endpointURL == "" || accessKey == "" || secretKey == "" {
		printUsage()
		os.Exit(1)
	}

	fmt.Println(strings.Repeat("=", 60))
	fmt.Println("MinIO S3 Compatibility Test using AWS SDK v2 for Go")
	fmt.Println(strings.Repeat("=", 60))
	fmt.Printf("Endpoint: %s\n", endpointURL)
	fmt.Printf("Access Key: %s\n", accessKey)
	fmt.Printf("Bucket: %s\n", bucketName)
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println()

	// Create S3 client
	client, err := createS3Client(endpointURL, accessKey, secretKey)
	if err != nil {
		log.Fatalf("Failed to create S3 client: %v", err)
	}

	// Create test runner
	runner := &TestRunner{
		client:     client,
		bucketName: bucketName,
		results:    make([]TestResult, 0),
	}

	// Run tests
	ctx := context.Background()
	runner.runTests(ctx)

	// Print summary
	runner.printSummary()
}

func createS3Client(endpointURL, accessKey, secretKey string) (*s3.Client, error) {
	// Create custom endpoint resolver
	customResolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
		return aws.Endpoint{
			URL:               endpointURL,
			HostnameImmutable: true,
			Source:            aws.EndpointSourceCustom,
		}, nil
	})

	// Load configuration with static credentials
	cfg, err := config.LoadDefaultConfig(context.Background(),
		config.WithRegion("us-east-1"),
		config.WithEndpointResolverWithOptions(customResolver),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKey, secretKey, "")),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	// Create S3 client with path-style addressing (required for MinIO)
	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.UsePathStyle = true
	})

	return client, nil
}

func (tr *TestRunner) runTests(ctx context.Context) {
	// Test 1: List buckets
	tr.testListBuckets(ctx)

	// Test 2: Create bucket
	tr.testCreateBucket(ctx)

	// Test 3: Upload object
	testKey := fmt.Sprintf("test-file-%s.txt", time.Now().Format("20060102-150405"))
	testContent := fmt.Sprintf("Hello from MinIO! Tested at %s", time.Now().Format(time.RFC3339))
	if !tr.testPutObject(ctx, testKey, testContent) {
		fmt.Println("\nSkipping remaining tests due to upload failure.")
		return
	}

	// Test 4: List objects
	tr.testListObjects(ctx)

	// Test 5: Get object
	tr.testGetObject(ctx, testKey, testContent)

	// Test 6: Head object (metadata)
	tr.testHeadObject(ctx, testKey)

	// Test 7: Copy object
	copyKey := testKey + ".copy"
	tr.testCopyObject(ctx, testKey, copyKey)

	// Test 8: Delete objects
	tr.testDeleteObjects(ctx, []string{testKey, copyKey})

	// Test 9: Delete bucket
	tr.testDeleteBucket(ctx)
}

func (tr *TestRunner) testListBuckets(ctx context.Context) {
	fmt.Println("Test 1: List Buckets")

	output, err := tr.client.ListBuckets(ctx, &s3.ListBucketsInput{})
	if err != nil {
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"List Buckets", false})
		return
	}

	bucketNames := make([]string, len(output.Buckets))
	for i, bucket := range output.Buckets {
		bucketNames[i] = *bucket.Name
	}

	fmt.Printf("✓ Success! Found %d bucket(s): %v\n\n", len(output.Buckets), bucketNames)
	tr.results = append(tr.results, TestResult{"List Buckets", true})
}

func (tr *TestRunner) testCreateBucket(ctx context.Context) {
	fmt.Printf("Test 2: Create Bucket '%s'\n", tr.bucketName)

	_, err := tr.client.CreateBucket(ctx, &s3.CreateBucketInput{
		Bucket: aws.String(tr.bucketName),
	})

	if err != nil {
		// Check if bucket already exists
		if strings.Contains(err.Error(), "BucketAlreadyOwnedByYou") || strings.Contains(err.Error(), "BucketAlreadyExists") {
			fmt.Printf("✓ Bucket '%s' already exists (owned by you)\n\n", tr.bucketName)
			tr.results = append(tr.results, TestResult{"Create Bucket", true})
			return
		}
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"Create Bucket", false})
		return
	}

	fmt.Printf("✓ Success! Created bucket '%s'\n\n", tr.bucketName)
	tr.results = append(tr.results, TestResult{"Create Bucket", true})
}

func (tr *TestRunner) testPutObject(ctx context.Context, key, content string) bool {
	fmt.Println("Test 3: Upload Object")

	_, err := tr.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(tr.bucketName),
		Key:         aws.String(key),
		Body:        bytes.NewReader([]byte(content)),
		ContentType: aws.String("text/plain"),
	})

	if err != nil {
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"Upload Object", false})
		return false
	}

	fmt.Printf("✓ Success! Uploaded object '%s'\n\n", key)
	tr.results = append(tr.results, TestResult{"Upload Object", true})
	return true
}

func (tr *TestRunner) testListObjects(ctx context.Context) {
	fmt.Printf("Test 4: List Objects in Bucket '%s'\n", tr.bucketName)

	output, err := tr.client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
		Bucket: aws.String(tr.bucketName),
	})

	if err != nil {
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"List Objects", false})
		return
	}

	fmt.Printf("✓ Success! Found %d object(s):\n", len(output.Contents))
	for i, obj := range output.Contents {
		if i < 5 {
			fmt.Printf("  - %s\n", *obj.Key)
		}
	}
	if len(output.Contents) > 5 {
		fmt.Printf("  ... and %d more\n", len(output.Contents)-5)
	}
	fmt.Println()

	tr.results = append(tr.results, TestResult{"List Objects", true})
}

func (tr *TestRunner) testGetObject(ctx context.Context, key, expectedContent string) {
	fmt.Printf("Test 5: Download Object '%s'\n", key)

	output, err := tr.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(tr.bucketName),
		Key:    aws.String(key),
	})

	if err != nil {
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"Download Object", false})
		return
	}
	defer output.Body.Close()

	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(output.Body)
	if err != nil {
		fmt.Printf("✗ Failed to read body: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"Download Object", false})
		return
	}

	downloadedContent := buf.String()
	if downloadedContent != expectedContent {
		fmt.Println("✗ Content mismatch!")
		fmt.Printf("  Expected: %s\n", expectedContent)
		fmt.Printf("  Got: %s\n\n", downloadedContent)
		tr.results = append(tr.results, TestResult{"Download Object", false})
		return
	}

	fmt.Println("✓ Success! Downloaded and verified content:")
	fmt.Printf("  Content: %s\n\n", downloadedContent)
	tr.results = append(tr.results, TestResult{"Download Object", true})
}

func (tr *TestRunner) testHeadObject(ctx context.Context, key string) {
	fmt.Printf("Test 6: Get Object Metadata '%s'\n", key)

	output, err := tr.client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(tr.bucketName),
		Key:    aws.String(key),
	})

	if err != nil {
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"Get Object Metadata", false})
		return
	}

	fmt.Println("✓ Success! Object metadata:")
	if output.ContentType != nil {
		fmt.Printf("  Content-Type: %s\n", *output.ContentType)
	}
	if output.ContentLength != nil {
		fmt.Printf("  Content-Length: %d bytes\n", *output.ContentLength)
	}
	if output.LastModified != nil {
		fmt.Printf("  Last-Modified: %s\n", output.LastModified.Format(time.RFC3339))
	}
	if output.ETag != nil {
		fmt.Printf("  ETag: %s\n", *output.ETag)
	}
	fmt.Println()

	tr.results = append(tr.results, TestResult{"Get Object Metadata", true})
}

func (tr *TestRunner) testCopyObject(ctx context.Context, sourceKey, destKey string) {
	fmt.Println("Test 7: Copy Object")

	copySource := fmt.Sprintf("%s/%s", tr.bucketName, sourceKey)
	_, err := tr.client.CopyObject(ctx, &s3.CopyObjectInput{
		Bucket:     aws.String(tr.bucketName),
		CopySource: aws.String(copySource),
		Key:        aws.String(destKey),
	})

	if err != nil {
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"Copy Object", false})
		return
	}

	fmt.Printf("✓ Success! Copied '%s' to '%s'\n\n", sourceKey, destKey)
	tr.results = append(tr.results, TestResult{"Copy Object", true})
}

func (tr *TestRunner) testDeleteObjects(ctx context.Context, keys []string) {
	fmt.Println("Test 8: Delete Objects")

	objects := make([]types.ObjectIdentifier, len(keys))
	for i, key := range keys {
		objects[i] = types.ObjectIdentifier{
			Key: aws.String(key),
		}
	}

	_, err := tr.client.DeleteObjects(ctx, &s3.DeleteObjectsInput{
		Bucket: aws.String(tr.bucketName),
		Delete: &types.Delete{
			Objects: objects,
		},
	})

	if err != nil {
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"Delete Objects", false})
		return
	}

	fmt.Println("✓ Success! Deleted test objects\n")
	tr.results = append(tr.results, TestResult{"Delete Objects", true})
}

func (tr *TestRunner) testDeleteBucket(ctx context.Context) {
	fmt.Printf("Test 9: Delete Bucket '%s'\n", tr.bucketName)

	_, err := tr.client.DeleteBucket(ctx, &s3.DeleteBucketInput{
		Bucket: aws.String(tr.bucketName),
	})

	if err != nil {
		fmt.Printf("✗ Failed: %v\n\n", err)
		tr.results = append(tr.results, TestResult{"Delete Bucket", false})
		return
	}

	fmt.Printf("✓ Success! Deleted bucket '%s'\n\n", tr.bucketName)
	tr.results = append(tr.results, TestResult{"Delete Bucket", true})
}

func (tr *TestRunner) printSummary() {
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println("TEST SUMMARY")
	fmt.Println(strings.Repeat("=", 60))

	passed := 0
	for _, result := range tr.results {
		status := "✗ FAIL"
		if result.Passed {
			status = "✓ PASS"
			passed++
		}
		fmt.Printf("%s: %s\n", status, result.Name)
	}

	total := len(tr.results)
	fmt.Println(strings.Repeat("=", 60))
	fmt.Printf("Results: %d/%d tests passed\n", passed, total)
	fmt.Println(strings.Repeat("=", 60))

	if passed == total {
		fmt.Println("\n🎉 All tests passed! MinIO is working correctly with AWS SDK v2 for Go")
		os.Exit(0)
	} else {
		fmt.Printf("\n⚠️  %d test(s) failed\n", total-passed)
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println("Usage:")
	fmt.Println("  go run test-s3-sdk.go <endpoint_url> <access_key> <secret_key> [bucket_name]")
	fmt.Println()
	fmt.Println("Or set environment variables:")
	fmt.Println("  export MINIO_ENDPOINT=http://1.2.3.4:80")
	fmt.Println("  export MINIO_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE")
	fmt.Println("  export MINIO_SECRET_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
	fmt.Println("  export MINIO_TEST_BUCKET=sdk-test-bucket-go  # optional")
	fmt.Println("  go run test-s3-sdk.go")
	fmt.Println()
	fmt.Println("Quick example after Terraform deployment:")
	fmt.Println("  cd tf")
	fmt.Println("  go run ../test-s3-sdk.go \\")
	fmt.Println("    $(terraform output -raw minio_s3_endpoint) \\")
	fmt.Println("    $(terraform output -raw minio_s3_access_key) \\")
	fmt.Println("    $(terraform output -raw minio_s3_secret_key)")
	fmt.Println()
	fmt.Println("Or build and run:")
	fmt.Println("  go build -o test-s3-sdk test-s3-sdk.go")
	fmt.Println("  ./test-s3-sdk <endpoint> <access_key> <secret_key>")
}

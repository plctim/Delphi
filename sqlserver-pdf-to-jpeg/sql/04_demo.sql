/* ============================================================================
   04 - End-to-end demo.
   Creates a sample table, loads a PDF into the column, and runs the converter.
   ============================================================================ */

USE [YourDatabase];   -- <-- change to your database
GO

-- Sample storage table (skip if you already have one).
IF OBJECT_ID(N'dbo.Documents', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Documents
    (
        DocId    INT IDENTITY(1, 1) PRIMARY KEY,
        FileName NVARCHAR(260)  NULL,
        PdfBytes VARBINARY(MAX) NOT NULL
    );
END
GO

-- Load a PDF from disk into the column (path must be readable by the SQL service account).
INSERT into Documents (FileName, PdfBytes)
SELECT N'sample.pdf', BulkColumn
FROM OPENROWSET(BULK N'C:\Temp\sample.pdf', SINGLE_BLOB) AS src;
GO

-- (A) Just stream the pages back to the client.
EXEC dbo.ConvertPdfToJpeg @DocId = 1, @Dpi = 150;
GO

-- (B) Capture the pages into a table and inspect sizes.
DECLARE @pages TABLE
(
    DocId      INT,
    PageNumber INT,
    JpegBytes  VARBINARY(MAX)
);

INSERT @pages (DocId, PageNumber, JpegBytes)
EXEC dbo.ConvertPdfToJpeg @DocId = 1, @Dpi = 150;

SELECT DocId,
       PageNumber,
       DATALENGTH(JpegBytes) AS JpegSizeBytes
FROM @pages
ORDER BY PageNumber;
GO

/* (C) Optional: persist each page to disk via OLE automation, or just store the
   rows in a JpegPages table. Example persistent sink:

   CREATE TABLE dbo.PdfPageImages
   (
       DocId      INT          NOT NULL,
       PageNumber INT          NOT NULL,
       JpegBytes  VARBINARY(MAX) NOT NULL,
       CONSTRAINT PK_PdfPageImages PRIMARY KEY (DocId, PageNumber)
   );

   INSERT dbo.PdfPageImages (DocId, PageNumber, JpegBytes)
   EXEC dbo.ConvertPdfToJpeg @DocId = 1, @Dpi = 150;
*/

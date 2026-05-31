/* ============================================================================
   03 - Wrapper stored procedure.
   Pulls one PDF out of a VARBINARY(MAX) column and returns one row per page.
   Adjust the table/column names in @input_data_1 to match your schema.
   ============================================================================ */

USE [YourDatabase];   -- <-- change to your database
GO

CREATE OR ALTER PROCEDURE dbo.ConvertPdfToJpeg
    @DocId       INT,
    @Dpi         INT = 150,
    @RenderImage BIT = 1,   -- 0 => JpegBytes returned as NULL, no image rendered
    @ExtractText BIT = 1    -- 0 => PageText returned as NULL, no text extracted
AS
BEGIN
    SET NOCOUNT ON;

    -- At least one output must be requested.
    IF @RenderImage = 0 AND @ExtractText = 0
        THROW 50005, 'Nothing to produce: both @RenderImage and @ExtractText are 0.', 1;

    EXEC sp_execute_external_script
        @language     = N'Java',
        @script       = N'com.porterlee.pdf.PdfToJpeg',
        -- The input query becomes the executor's input dataset.
        -- @id is supplied through @params below.
        @input_data_1 = N'SELECT DocId, PdfBytes FROM dbo.Documents WHERE DocId = @id',
        @params       = N'@id INT, @dpi INT, @renderImage BIT, @extractText BIT',
        @id           = @DocId,
        @dpi          = @Dpi,
        @renderImage  = @RenderImage,
        @extractText  = @ExtractText
    WITH RESULT SETS (
        (
            DocId      INT,
            PageNumber INT,
            JpegBytes  VARBINARY(MAX),   -- NULL when @RenderImage = 0
            PageText   NVARCHAR(MAX)     -- NULL when @ExtractText = 0
        )
    );
END
GO

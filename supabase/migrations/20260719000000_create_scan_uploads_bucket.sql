INSERT INTO storage.buckets (id, name, public, allowed_mime_types)
VALUES ('scan-uploads', 'scan-uploads', false, ARRAY['image/jpeg', 'application/pdf'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "scan_uploads_insert_own" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'scan-uploads' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "scan_uploads_select_own" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'scan-uploads' AND (storage.foldername(name))[1] = auth.uid()::text);

class AnalysisController < ApplicationController
  # Maximum image size: 5MB
  MAX_IMAGE_SIZE = 5 * 1024 * 1024

  def analyze
    image_b64, media_type = extract_image
    return if performed?   # extract_image already rendered an error

    result = ClaudeService.analyze_stock(image_b64, media_type)

    if result[:success]
      render json: result, status: :ok
    else
      render json: result, status: :unprocessable_entity
    end
  end

  private

  def extract_image
    if params[:image].present?
      # Multipart form upload
      file = params[:image]
      if file.size > MAX_IMAGE_SIZE
        render json: { error: 'Image too large. Maximum 5MB.' }, status: :bad_request
        return [nil, nil]
      end
      [Base64.strict_encode64(file.read), file.content_type]

    elsif params[:image_base64].present?
      # Base64 JSON upload
      [params[:image_base64], params[:media_type] || 'image/jpeg']

    else
      render json: { error: 'No image provided. Send image as multipart form or image_base64 field.' },
             status: :bad_request
      [nil, nil]
    end
  end
end

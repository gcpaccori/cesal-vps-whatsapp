FROM python:3.11-slim

# tesseract-ocr-spa: el OCR tiene que entender español, si no lee "riego" como
# cualquier cosa. poppler-utils da pdftotext y pdftoppm. libreoffice queda como
# recurso para formatos antiguos (.doc, .xls).
RUN apt-get update && apt-get install -y --no-install-recommends \
        tesseract-ocr \
        tesseract-ocr-spa \
        poppler-utils \
        libreoffice-calc \
        libreoffice-writer \
        fonts-dejavu-core \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir flask==3.0.3 gunicorn==22.0.0 openpyxl==3.1.5 python-docx==1.1.2

WORKDIR /app
COPY app.py /app/app.py

# Un OCR de 25 páginas tarda; el timeout largo evita cortar a mitad.
CMD ["gunicorn", "-b", "0.0.0.0:8090", "-w", "2", "-t", "600", "app:app"]

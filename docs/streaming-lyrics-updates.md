# Streaming, testi e aggiornamenti Windows

## Musica online

In **Cerca**, scegliere **Online · Audius**, **YouTube** oppure **La mia libreria**.
Audius espone brani che gli artisti rendono pubblicamente riproducibili: non serve
una chiave API o un abbonamento WAVEIFY. Gli audio partono in streaming; non serve
importarli prima. I brani riservati, bloccati o non disponibili vengono esclusi.
Il catalogo non equivale ai cataloghi a pagamento di altri servizi.

YouTube resta una sorgente separata: ricerca/riproduzione dipendono dalla sua
disponibilità e dalle restrizioni della rete/provider. Un errore non viene
mascherato riproducendo una registrazione diversa. Si possono incollare anche
URL HTTP(S) diretti a file audio. I brani cloud personali continuano a utilizzare
URL privati firmati Supabase. Non sono stati aggiunti annunci o SDK pubblicitari.

Preferiti e playlist conservano gli identificativi online. Prima di riprodurre
un brano Audius viene verificata la disponibilità e risolto un URL aggiornato.
Il download offline è disabilitato quando il provider permette solo streaming;
questa condizione viene ricontrollata prima di scaricare.

## Testi

Dal player aprire **Testi**. I testi locali LRC e il backend hanno precedenza;
LRCLIB viene interrogato anche quando il backend fallisce. Titolo, artista e
durata devono corrispondere alla registrazione. Quando esistono timestamp reali,
la riga attiva segue la posizione audio e gli spostamenti avanti/indietro; toccare
una riga sposta il player al suo timestamp. Lo scorrimento manuale sospende per
quattro secondi quello automatico. L'offset manuale resta nelle impostazioni.
Testi semplici e brani strumentali sono riconosciuti senza simulare sincronismo.
La copertura dipende dal catalogo dei testi e non è garantita per ogni brano.

## Aggiornamenti Windows

Installare la versione 1.1.0 **sopra quella precedente**, mantenendo la stessa
cartella: non disinstallare. È il passaggio iniziale necessario per aggiungere
il nuovo updater alla vecchia applicazione. In seguito, da **Impostazioni**:

1. Controllare gli aggiornamenti (il controllo viene eseguito anche all'avvio,
   al massimo una volta ogni 12 ore).
2. Scaricare l'aggiornamento proposto.
3. Scegliere **Riavvia e installa** dopo la verifica.

Il feed `update.json` e gli installer provengono dalle Release di questo
repository GitHub. Il client convalida host HTTPS, versione, dimensione e SHA-256;
il programma di installazione viene ricontrollato subito prima dell'esecuzione.
Un helper esterno attende la chiusura dell'app, esegue Inno Setup nella cartella
esistente e riavvia l'app. Libreria e impostazioni restano nei documenti/dati utente.
L'installer è privo di certificato Authenticode; il controllo SHA-256 non equivale
a una firma Authenticode. Le installazioni in cartelle protette possono richiedere
permessi amministrativi; quella standard per utente non richiede disinstallazione.
Android conserva l'integrazione Google Play; il nuovo flusso GitHub è Windows.

## Verifica e rilascio

Il workflow desktop esegue analisi, test e una build Windows. Verifica il decoder
con audio locale e streaming reale Audius, e ottiene timestamp reali LRCLIB senza
stampare testi nei log. Prova inoltre l'helper di aggiornamento su un'installazione
precedente, controlla riavvio, permanenza di libreria/impostazioni e dimensioni
della finestra. Il manifest viene calcolato dai byte dello stesso installer testato.

Per un rilascio, incrementare `pubspec.yaml` e creare il tag corrispondente
(es. `v1.1.0+2`); pubblicare installer, ZIP portatile e `update.json` della build
verificata. Il workflow **Verify published Windows update** controlla anche il
feed pubblico e scarica/verifica l'installer con il client compilato.
